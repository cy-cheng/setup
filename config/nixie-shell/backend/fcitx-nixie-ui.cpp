#include <fcitx-utils/event.h>
#include <cctype>
#include <fcitx/addonfactory.h>
#include <fcitx/addoninstance.h>
#include <fcitx/addonmanager.h>
#include <fcitx/candidatelist.h>
#include <fcitx/event.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputmethodentry.h>
#include <fcitx/inputpanel.h>
#include <fcitx/instance.h>
#include <fcitx/userinterface.h>

#include "fcitx-wayland-popup.hpp"

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <vector>

namespace {

std::string socketPath() {
    if (const char *runtime = std::getenv("XDG_RUNTIME_DIR"); runtime && *runtime) {
        return std::string(runtime) + "/nixie-fcitx.sock";
    }
    return "/tmp/nixie-fcitx-" + std::to_string(getuid()) + ".sock";
}

std::string escape(const std::string &value) {
    std::string out;
    out.reserve(value.size() + 8);
    for (unsigned char c : value) {
        switch (c) {
        case '\\': out += "\\\\"; break;
        case '"': out += "\\\""; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        default:
            if (c >= 0x20) out += static_cast<char>(c);
        }
    }
    return out;
}

void sendMessage(const std::string &message) {
    int fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    if (fd < 0) return;
    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    const auto path = socketPath();
    if (path.size() < sizeof(address.sun_path)) {
        std::memcpy(address.sun_path, path.c_str(), path.size() + 1);
        sendto(fd, message.data(), message.size(), MSG_DONTWAIT,
               reinterpret_cast<sockaddr *>(&address), sizeof(address));
    }
    close(fd);
}

} // namespace

class NixieUI final : public fcitx::UserInterface {
public:
    explicit NixieUI(fcitx::Instance *instance) : instance_(instance) {
        nativePopup_ = std::make_unique<NativeCandidatePopup>(instance_);
        keyWatcher_ = instance_->watchEvent(
            fcitx::EventType::InputContextKeyEvent,
            fcitx::EventWatcherPhase::PreInputMethod,
            [this](fcitx::Event &event) { handleKey(static_cast<fcitx::KeyEvent &>(event)); });
        // Show the "input method" label at the text cursor on every user switch, including
        // ones that come from outside Fcitx (Caps Lock is bound in Hyprland to
        // `fcitx5-remote -t`, which doesn't go through Fcitx's own trigger-key path).
        switchWatcher_ = instance_->watchEvent(
            fcitx::EventType::InputContextSwitchInputMethod,
            fcitx::EventWatcherPhase::PostInputMethod,
            [this](fcitx::Event &event) {
                auto &e = static_cast<fcitx::InputContextSwitchInputMethodEvent &>(event);
                if (e.reason() == fcitx::InputMethodSwitchedReason::CapabilityChanged) return;
                auto *ic = e.inputContext();
                if (!ic) return;
                // Defer one tick: the new engine's activate() resets the panel right after
                // this event, which would wipe the label.
                infoRef_ = ic->watch();
                infoDefer_ = instance_->eventLoop().addDeferEvent([this](fcitx::EventSource *) {
                    showSwitchLabel();
                    infoDefer_.reset();
                    return true;
                });
            });
    }

    bool available() override { return true; }
    void suspend() override {
        nativePopup_->hide();
        sendMessage("{\"type\":\"candidates\",\"visible\":false}");
    }
    void resume() override {}

    void update(fcitx::UserInterfaceComponent component, fcitx::InputContext *ic) override {
        if (component != fcitx::UserInterfaceComponent::InputPanel) return;
        publish(ic);
    }

private:
    // Short label for the current input method ("注", "EN", …), shown at the cursor for
    // ~1.2 s after a switch, then cleared if nothing else replaced it.
    void showSwitchLabel() {
        auto *ic = infoRef_.get();
        if (!ic) return;
        const auto *entry = instance_->inputMethodEntry(ic);
        if (!entry) return;
        // One symbol, the same as the bar's input-method indicator.
        const std::string &id = entry->uniqueName();
        std::string label = id == "rime" ? "注" : id == "mozc" ? "あ"
                          : id == "keyboard-us" ? "EN" : id == "keyboard-de" ? "DE"
                          : (entry->label().empty() ? entry->name() : entry->label());
        shownLabel_ = label;
        auto &panel = ic->inputPanel();
        if (panel.candidateList() || !panel.preedit().empty()) return;   // already typing: don't interrupt
        panel.setAuxUp(fcitx::Text(label));
        ic->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel, true);
        infoHide_ = instance_->eventLoop().addTimeEvent(
            CLOCK_MONOTONIC, fcitx::now(CLOCK_MONOTONIC) + 1200000, 0,
            [this](fcitx::EventSourceTime *, uint64_t) {
                if (auto *ic2 = infoRef_.get()) {
                    auto &p2 = ic2->inputPanel();
                    if (p2.auxUp().toString() == shownLabel_ && !p2.candidateList() && p2.preedit().empty()) {
                        p2.setAuxUp(fcitx::Text());
                        ic2->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel, true);
                    }
                }
                infoHide_.reset();
                return true;
            });
    }

    void publish(fcitx::InputContext *ic) {
        if (!ic) {
            nativePopup_->hide();
            sendMessage("{\"type\":\"candidates\",\"visible\":false}");
            return;
        }
        auto &panel = ic->inputPanel();
        auto candidates = panel.candidateList();
        if (panel.empty() ||
            (!candidates && panel.preedit().empty() && panel.clientPreedit().empty() &&
             panel.auxUp().empty() && panel.auxDown().empty())) {
            expanded_ = false;
            page_ = 1;
            nativePopup_->hide();
            sendMessage("{\"type\":\"candidates\",\"visible\":false}");
            return;
        }
        if (nativePopup_->render(ic, expanded_, page_)) {
            sendMessage("{\"type\":\"candidates\",\"visible\":false}");
            return;
        }
        const auto &rect = ic->cursorRect();
        std::string json = "{\"type\":\"candidates\",\"visible\":true,\"expanded\":";
        json += expanded_ ? "true" : "false";
        json += ",\"x\":" + std::to_string(rect.left());
        json += ",\"y\":" + std::to_string(rect.bottom());
        json += ",\"scale\":" + std::to_string(ic->scaleFactor());
        const auto preedit = panel.clientPreedit().empty()
                                 ? panel.preedit().toString()
                                 : panel.clientPreedit().toString();
        json += ",\"preedit\":\"" + escape(preedit) + "\"";
        json += ",\"aux\":\"" + escape(panel.auxUp().toString() + panel.auxDown().toString()) + "\"";
        json += ",\"cursor\":" + std::to_string(candidates ? candidates->cursorIndex() : -1);
        auto *pageable = candidates ? candidates->toPageable() : nullptr;
        int currentPage = pageable ? pageable->currentPage() : -1;
        if (currentPage >= 0) page_ = currentPage + 1;
        json += ",\"page\":" + std::to_string(page_);
        json += ",\"has_prev\":" + std::string(pageable && pageable->hasPrev() ? "true" : "false");
        json += ",\"has_next\":" + std::string(pageable && pageable->hasNext() ? "true" : "false");
        json += ",\"items\":[";
        if (candidates) {
            const int limit = expanded_ ? 25 : 7;
            for (int i = 0; i < std::min(candidates->size(), limit); ++i) {
                if (i) json += ',';
                const std::string index(1, static_cast<char>('A' + i));
                json += "{\"label\":\"" + index + "\",\"text\":\"" + escape(candidates->candidate(i).textWithComment("  ").toString()) + "\"}";
            }
        }
        json += "]}";
        sendMessage(json);
    }

    void setCursor(const std::shared_ptr<fcitx::CandidateList> &list, int index) {
        index = std::clamp(index, 0, std::max(0, list->size() - 1));
        if (auto *modifiable = list->toCursorModifiable()) {
            modifiable->setCursorIndex(index);
            return;
        }
        if (auto *movable = list->toCursorMovable()) {
            int current = std::max(0, list->cursorIndex());
            while (current < index) { movable->nextCandidate(); ++current; }
            while (current > index) { movable->prevCandidate(); --current; }
        }
    }

    void handleKey(fcitx::KeyEvent &event) {
        if (event.isRelease()) return;
        auto *ic = event.inputContext();
        if (!ic) return;
        const auto key = event.key();
        const auto normalizedKey = key.normalize();
        auto &panel = ic->inputPanel();
        if (key.check(FcitxKey_Return, fcitx::KeyState::Ctrl) ||
            key.check(FcitxKey_KP_Enter, fcitx::KeyState::Ctrl)) {
            const auto raw = panel.clientPreedit().empty()
                                 ? panel.preedit().toString()
                                 : panel.clientPreedit().toString();
            if (!raw.empty()) {
                ic->commitString(raw);
                ic->reset();
                expanded_ = false;
                page_ = 1;
                event.filterAndAccept();
                sendMessage("{\"type\":\"candidates\",\"visible\":false}");
            }
            return;
        }
        auto list = panel.candidateList();
        if (!list || list->empty()) return;
        if (!expanded_ && key.check(FcitxKey_Down)) {
            expanded_ = true;
            page_ = 1;
            if (list->cursorIndex() < 0) setCursor(list, 0);
            event.filterAndAccept();
        } else if (!expanded_ && key.check(FcitxKey_Left)) {
            setCursor(list, std::max(0, list->cursorIndex() - 1));
            event.filterAndAccept();
        } else if (!expanded_ && key.check(FcitxKey_Right)) {
            setCursor(list, std::min(std::min(6, list->size() - 1), list->cursorIndex() + 1));
            event.filterAndAccept();
        } else if (expanded_ && key.check(FcitxKey_Escape)) {
            expanded_ = false;
            setCursor(list, std::min(6, std::max(0, list->cursorIndex())));
            event.filterAndAccept();
        } else if (expanded_ && key.check(FcitxKey_Left)) {
            setCursor(list, list->cursorIndex() - 1); event.filterAndAccept();
        } else if (expanded_ && key.check(FcitxKey_Right)) {
            setCursor(list, list->cursorIndex() + 1); event.filterAndAccept();
        } else if (expanded_ && key.check(FcitxKey_Up)) {
            const int cursor = std::max(0, list->cursorIndex());
            if (cursor >= 5) {
                setCursor(list, cursor - 5);
            } else if (auto *pageable = list->toPageable(); pageable && pageable->hasPrev()) {
                const int column = cursor % 5;
                pageable->prev();
                page_ = std::max(1, page_ - 1);
                setCursor(list, std::max(0, list->size() - 5 + column));
            }
            event.filterAndAccept();
        } else if (expanded_ && key.check(FcitxKey_Down)) {
            const int cursor = std::max(0, list->cursorIndex());
            if (cursor + 5 < list->size()) {
                setCursor(list, cursor + 5);
            } else if (auto *pageable = list->toPageable(); pageable && pageable->hasNext()) {
                const int column = cursor % 5;
                pageable->next();
                ++page_;
                setCursor(list, std::min(column, std::max(0, list->size() - 1)));
            }
            event.filterAndAccept();
        } else if (expanded_ && (key.check(FcitxKey_Page_Up) || key.check(FcitxKey_Page_Down))) {
            if (auto *pageable = list->toPageable()) {
                if (key.check(FcitxKey_Page_Up) && pageable->hasPrev()) {
                    pageable->prev(); page_ = std::max(1, page_ - 1);
                }
                if (key.check(FcitxKey_Page_Down) && pageable->hasNext()) {
                    pageable->next(); ++page_;
                }
                setCursor(list, 0);
            }
            event.filterAndAccept();
        } else if (normalizedKey.states() == fcitx::KeyState::NoState &&
                   normalizedKey.sym() >= FcitxKey_A && normalizedKey.sym() <= FcitxKey_Y) {
            // Fcitx normalizes Shift+A..Y to an uppercase keysym without the
            // Shift state. Match the uppercase symbol shown in the candidate
            // labels; bare lowercase letters must remain available to the IM.
            const int index = static_cast<int>(normalizedKey.sym() - FcitxKey_A);
            const int visible = std::min(list->size(), expanded_ ? 25 : 7);
            if (index < visible) {
                list->candidate(index).select(ic);
                expanded_ = false;
                page_ = 1;
                event.filterAndAccept();
            } else {
                return;
            }
        } else if (expanded_ && (key.check(FcitxKey_Return) || key.check(FcitxKey_KP_Enter))) {
            int cursor = std::clamp(list->cursorIndex(), 0, list->size() - 1);
            list->candidate(cursor).select(ic);
            expanded_ = false;
            event.filterAndAccept();
        } else {
            return;
        }
        ic->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel, true);
        publish(ic);
    }

    fcitx::Instance *instance_;
    bool expanded_ = false;
    int page_ = 1;
    std::unique_ptr<NativeCandidatePopup> nativePopup_;
    std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>> keyWatcher_;
    std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>> switchWatcher_;
    fcitx::TrackableObjectReference<fcitx::InputContext> infoRef_;
    std::unique_ptr<fcitx::EventSource> infoDefer_;
    std::unique_ptr<fcitx::EventSourceTime> infoHide_;
    std::string shownLabel_;
};

class NixieUIFactory final : public fcitx::AddonFactory {
public:
    fcitx::AddonInstance *create(fcitx::AddonManager *manager) override {
        return new NixieUI(manager->instance());
    }
};

FCITX_ADDON_FACTORY(NixieUIFactory)
