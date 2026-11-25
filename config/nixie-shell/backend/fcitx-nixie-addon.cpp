#include <fcitx/addonfactory.h>
#include <fcitx/addoninstance.h>
#include <fcitx/addonmanager.h>
#include <fcitx/event.h>
#include <fcitx/instance.h>

#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <vector>

namespace {

const char *labelFor(int state, const std::string &method) {
    if (state != 2) {
        return "EN";
    }
    if (method.find("keyboard-de") != std::string::npos) {
        return "DE";
    }
    if (method.find("rime") != std::string::npos ||
        method.find("chewing") != std::string::npos) {
        return "中";
    }
    if (method.find("mozc") != std::string::npos) {
        return "日";
    }
    return "EN";
}

std::string socketPath() {
    if (const char *runtime = std::getenv("XDG_RUNTIME_DIR");
        runtime != nullptr && runtime[0] != '\0') {
        return std::string(runtime) + "/nixie-fcitx.sock";
    }
    return "/tmp/nixie-fcitx-" + std::to_string(getuid()) + ".sock";
}

} // namespace

class NixieStatus final : public fcitx::AddonInstance {
public:
    explicit NixieStatus(fcitx::Instance *instance) : instance_(instance) {
        using fcitx::EventType;
        using fcitx::EventWatcherPhase;

        const EventType events[] = {
            EventType::InputContextInputMethodActivated,
            EventType::InputContextInputMethodDeactivated,
            EventType::InputContextSwitchInputMethod,
            EventType::InputContextFocusIn,
            EventType::FocusGroupFocusChanged,
            EventType::InputMethodGroupChanged,
        };
        for (EventType type : events) {
            watchers_.push_back(instance_->watchEvent(
                type, EventWatcherPhase::PostInputMethod,
                [this](fcitx::Event &) { emit(); }));
        }
    }

private:
    void emit() const {
        const int state = instance_->state();
        const std::string method = instance_->currentInputMethod();
        const std::string message =
            std::string("{\"type\":\"status\",\"active\":") + (state == 2 ? "true" : "false") +
            ",\"name\":\"" + method + "\",\"label\":\"" +
            labelFor(state, method) + "\"}";

        int fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
        if (fd < 0) {
            return;
        }
        struct sockaddr_un address = {};
        address.sun_family = AF_UNIX;
        const std::string path = socketPath();
        if (path.size() < sizeof(address.sun_path)) {
            std::memcpy(address.sun_path, path.c_str(), path.size() + 1);
            sendto(fd, message.data(), message.size(), MSG_DONTWAIT,
                   reinterpret_cast<struct sockaddr *>(&address),
                   sizeof(address));
        }
        close(fd);
    }

    fcitx::Instance *instance_;
    std::vector<std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>>>
        watchers_;
};

class NixieStatusFactory final : public fcitx::AddonFactory {
public:
    fcitx::AddonInstance *create(fcitx::AddonManager *manager) override {
        return new NixieStatus(manager->instance());
    }
};

FCITX_ADDON_FACTORY(NixieStatusFactory)
