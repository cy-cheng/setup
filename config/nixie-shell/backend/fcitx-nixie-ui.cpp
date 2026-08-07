#include <fcitx/addonfactory.h>
#include <fcitx/addoninstance.h>
#include <fcitx/addonmanager.h>
#include <fcitx/candidatelist.h>
#include <fcitx/event.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputpanel.h>
#include <fcitx/instance.h>
#include <fcitx/userinterface.h>

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
        keyWatcher_ = instance_->watchEvent(
            fcitx::EventType::InputContextKeyEvent,
            fcitx::EventWatcherPhase::PreInputMethod,
            [this](fcitx::Event &event) { handleKey(static_cast<fcitx::KeyEvent &>(event)); });
    }

    bool available() override { return true; }
    void suspend() override { sendMessage("{\"type\":\"candidates\",\"visible\":false}"); }
    void resume() override {}

    void update(fcitx::UserInterfaceComponent component, fcitx::InputContext *ic) override {
        if (component != fcitx::UserInterfaceComponent::InputPanel) return;
        publish(ic);
    }

private:
    void publish(fcitx::InputContext *ic) {
        if (!ic) {
            sendMessage("{\"type\":\"candidates\",\"visible\":false}");
            return;
        }
        auto &panel = ic->inputPanel();
        auto candidates = panel.candidateList();
        if (panel.empty() || (!candidates && panel.preedit().empty() && panel.auxUp().empty())) {
            expanded_ = false;
            sendMessage("{\"type\":\"candidates\",\"visible\":false}");
            return;
        }
        const auto &rect = ic->cursorRect();
        std::string json = "{\"type\":\"candidates\",\"visible\":true,\"expanded\":";
        json += expanded_ ? "true" : "false";
        json += ",\"x\":" + std::to_string(rect.left());
        json += ",\"y\":" + std::to_string(rect.bottom());
        json += ",\"scale\":" + std::to_string(ic->scaleFactor());
        json += ",\"preedit\":\"" + escape(panel.preedit().toString()) + "\"";
        json += ",\"aux\":\"" + escape(panel.auxUp().toString() + panel.auxDown().toString()) + "\"";
        json += ",\"cursor\":" + std::to_string(candidates ? candidates->cursorIndex() : -1);
        json += ",\"items\":[";
        if (candidates) {
            for (int i = 0; i < candidates->size(); ++i) {
                if (i) json += ',';
                json += "{\"label\":\"" + escape(candidates->label(i).toString()) + "\",\"text\":\"" + escape(candidates->candidate(i).textWithComment("  ").toString()) + "\"}";
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
        auto list = ic->inputPanel().candidateList();
        if (!list || list->empty()) return;
        const auto key = event.key();
        if (!expanded_ && key.check(FcitxKey_Down)) {
            expanded_ = true;
            if (list->cursorIndex() < 0) setCursor(list, 0);
            event.filterAndAccept();
        } else if (expanded_ && key.check(FcitxKey_Escape)) {
            expanded_ = false;
            event.filterAndAccept();
        } else if (expanded_ && key.check(FcitxKey_Left)) {
            setCursor(list, list->cursorIndex() - 1); event.filterAndAccept();
        } else if (expanded_ && key.check(FcitxKey_Right)) {
            setCursor(list, list->cursorIndex() + 1); event.filterAndAccept();
        } else if (expanded_ && key.check(FcitxKey_Up)) {
            setCursor(list, list->cursorIndex() - 4); event.filterAndAccept();
        } else if (expanded_ && key.check(FcitxKey_Down)) {
            setCursor(list, list->cursorIndex() + 4); event.filterAndAccept();
        } else if (expanded_ && (key.check(FcitxKey_Page_Up) || key.check(FcitxKey_Page_Down))) {
            if (auto *pageable = list->toPageable()) {
                if (key.check(FcitxKey_Page_Up) && pageable->hasPrev()) pageable->prev();
                if (key.check(FcitxKey_Page_Down) && pageable->hasNext()) pageable->next();
                setCursor(list, 0);
            }
            event.filterAndAccept();
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
    std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>> keyWatcher_;
};

class NixieUIFactory final : public fcitx::AddonFactory {
public:
    fcitx::AddonInstance *create(fcitx::AddonManager *manager) override {
        return new NixieUI(manager->instance());
    }
};

FCITX_ADDON_FACTORY(NixieUIFactory)
