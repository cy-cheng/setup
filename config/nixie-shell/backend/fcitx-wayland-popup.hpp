#pragma once

#include <memory>

namespace fcitx {
class InputContext;
class Instance;
}  // namespace fcitx

class NativeCandidatePopup {
   public:
    explicit NativeCandidatePopup(fcitx::Instance* instance);
    ~NativeCandidatePopup();

    NativeCandidatePopup(const NativeCandidatePopup&) = delete;
    NativeCandidatePopup& operator=(const NativeCandidatePopup&) = delete;

    bool render(fcitx::InputContext* ic, bool expanded, int page);
    void hide();

   private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};
