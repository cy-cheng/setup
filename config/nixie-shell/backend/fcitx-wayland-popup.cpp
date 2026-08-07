#include "fcitx-wayland-popup.hpp"

#include <Fcitx5/Module/fcitx-module/wayland/wayland_public.h>
#include <cairo/cairo.h>
#include <fcitx-utils/handlertable.h>
#include <fcitx-utils/metastring.h>
#include <fcitx-utils/misc.h>
#include <fcitx-utils/signals.h>
#include <fcitx/addoninstance.h>
#include <fcitx/addonmanager.h>
#include <fcitx/candidatelist.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputpanel.h>
#include <fcitx/instance.h>
#include <pango/pangocairo.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <wayland-client.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

struct zwp_input_method_v2;
struct zwp_input_popup_surface_v2;

namespace fcitx::wayland {

// This mirrors Fcitx 5.1's generated wrapper. We only use the inline raw
// pointer accessor; ownership remains entirely with the waylandim addon.
class ZwpInputMethodV2 final {
   public:
    using wlType = zwp_input_method_v2;
    operator zwp_input_method_v2*() { return data_.get(); }

   private:
    static void destructor(zwp_input_method_v2*);
    Signal<void()> activateSignal_;
    Signal<void()> deactivateSignal_;
    Signal<void(const char*, uint32_t, uint32_t)> surroundingTextSignal_;
    Signal<void(uint32_t)> textChangeCauseSignal_;
    Signal<void(uint32_t, uint32_t)> contentTypeSignal_;
    Signal<void()> doneSignal_;
    Signal<void()> unavailableSignal_;
    uint32_t version_;
    void* userData_ = nullptr;
    UniqueCPtr<zwp_input_method_v2, &destructor> data_;
};

static inline zwp_input_method_v2* rawPointer(ZwpInputMethodV2* value) {
    return value ? static_cast<zwp_input_method_v2*>(*value) : nullptr;
}

}  // namespace fcitx::wayland

FCITX_ADDON_DECLARE_FUNCTION(WaylandIMModule, getInputMethodV2,
                             fcitx::wayland::ZwpInputMethodV2*(fcitx::InputContext*));

namespace {

constexpr uint32_t kGetInputPopupSurface = 4;
constexpr uint32_t kPopupDestroy = 0;

const wl_message kPopupRequests[] = {{"destroy", "", nullptr}};
const wl_message kPopupEvents[] = {
    {"text_input_rectangle", "iiii", nullptr},
};
const wl_interface kPopupInterface = {
    "zwp_input_popup_surface_v2", 1, 1, kPopupRequests, 1, kPopupEvents,
};

zwp_input_popup_surface_v2* createInputPopup(zwp_input_method_v2* method, wl_surface* surface) {
    auto* proxy =
        wl_proxy_marshal_flags(reinterpret_cast<wl_proxy*>(method), kGetInputPopupSurface, &kPopupInterface,
                               wl_proxy_get_version(reinterpret_cast<wl_proxy*>(method)), 0, nullptr, surface);
    return reinterpret_cast<zwp_input_popup_surface_v2*>(proxy);
}

void destroyInputPopup(zwp_input_popup_surface_v2* popup) {
    if (!popup) return;
    auto* proxy = reinterpret_cast<wl_proxy*>(popup);
    wl_proxy_marshal_flags(proxy, kPopupDestroy, nullptr, wl_proxy_get_version(proxy), WL_MARSHAL_FLAG_DESTROY);
}

struct ShmBuffer {
    wl_buffer* buffer = nullptr;
    void* data = MAP_FAILED;
    size_t size = 0;

    ~ShmBuffer() {
        if (buffer) wl_buffer_destroy(buffer);
        if (data != MAP_FAILED) munmap(data, size);
    }
};

void releaseBuffer(void* data, wl_buffer*) { delete static_cast<ShmBuffer*>(data); }

const wl_buffer_listener kBufferListener = {.release = releaseBuffer};

int anonymousFile(size_t size) {
    int fd = static_cast<int>(syscall(SYS_memfd_create, "nixie-candidates", 1));
    if (fd < 0) return -1;
    if (ftruncate(fd, static_cast<off_t>(size)) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

void roundedRect(cairo_t* cr, double x, double y, double width, double height, double radius) {
    constexpr double k = 0.5522847498;
    cairo_new_sub_path(cr);
    cairo_move_to(cr, x + radius, y);
    cairo_line_to(cr, x + width - radius, y);
    cairo_curve_to(cr, x + width - radius + radius * k, y, x + width, y + radius - radius * k, x + width, y + radius);
    cairo_line_to(cr, x + width, y + height - radius);
    cairo_curve_to(cr, x + width, y + height - radius + radius * k, x + width - radius + radius * k, y + height,
                   x + width - radius, y + height);
    cairo_line_to(cr, x + radius, y + height);
    cairo_curve_to(cr, x + radius - radius * k, y + height, x, y + height - radius + radius * k, x,
                   y + height - radius);
    cairo_line_to(cr, x, y + radius);
    cairo_curve_to(cr, x, y + radius - radius * k, x + radius - radius * k, y, x + radius, y);
    cairo_close_path(cr);
}

void color(cairo_t* cr, double r, double g, double b, double a = 1.0) { cairo_set_source_rgba(cr, r, g, b, a); }

struct TextMetrics {
    int width = 0;
    int height = 0;
};

PangoFontDescription* font(double size, bool bold = false) {
    auto* description = pango_font_description_new();
    pango_font_description_set_family(description, "Noto Sans Mono");
    pango_font_description_set_size(description, static_cast<int>(size * PANGO_SCALE));
    pango_font_description_set_weight(description, bold ? PANGO_WEIGHT_BOLD : PANGO_WEIGHT_NORMAL);
    return description;
}

TextMetrics measure(cairo_t* cr, std::string_view text, double size, bool bold = false) {
    auto* layout = pango_cairo_create_layout(cr);
    auto* description = font(size, bold);
    pango_layout_set_font_description(layout, description);
    pango_layout_set_text(layout, text.data(), static_cast<int>(text.size()));
    int width = 0, height = 0;
    pango_layout_get_pixel_size(layout, &width, &height);
    pango_font_description_free(description);
    g_object_unref(layout);
    return {width, height};
}

void drawText(cairo_t* cr, std::string_view text, double x, double y, double width, double size, bool bold,
              bool selected) {
    auto* layout = pango_cairo_create_layout(cr);
    auto* description = font(size, bold);
    pango_layout_set_font_description(layout, description);
    pango_layout_set_text(layout, text.data(), static_cast<int>(text.size()));
    pango_layout_set_width(layout, static_cast<int>(std::max(1.0, width) * PANGO_SCALE));
    pango_layout_set_single_paragraph_mode(layout, true);
    pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END);
    color(cr, selected ? 0.027 : 0.91, selected ? 0.024 : 0.87, selected ? 0.020 : 0.82);
    cairo_move_to(cr, x, y);
    pango_cairo_show_layout(cr, layout);
    pango_font_description_free(description);
    g_object_unref(layout);
}

struct Candidate {
    std::string label;
    std::string text;
    std::string display;
};

}  // namespace

class NativeCandidatePopup::Impl {
   public:
    explicit Impl(fcitx::Instance* instance) : instance_(instance) {
        auto* wayland = instance_->addonManager().addon("wayland", true);
        if (!wayland) return;
        connectionCreated_ = wayland->call<fcitx::IWaylandModule::addConnectionCreatedCallback>(
            [this](const std::string&, wl_display* display, fcitx::FocusGroup*) {
                if (!display_) setupDisplay(display);
            });
        connectionClosed_ = wayland->call<fcitx::IWaylandModule::addConnectionClosedCallback>(
            [this](const std::string&, wl_display* display) {
                if (display_ == display) resetDisplay();
            });
    }

    ~Impl() { resetDisplay(); }

    bool render(fcitx::InputContext* ic, bool expanded, int page) {
        if (!ic || ic->frontendName() != "wayland_v2" || !display_ || !compositor_ || !shm_) {
            return false;
        }
        auto* waylandim = instance_->addonManager().addon("waylandim", true);
        if (!waylandim) return false;
        auto* wrapper = waylandim->call<fcitx::IWaylandIMModule::getInputMethodV2>(ic);
        auto* method = fcitx::wayland::rawPointer(wrapper);
        if (!method || !ensureSurface(method)) return false;

        auto& panel = ic->inputPanel();
        auto list = panel.candidateList();
        std::vector<Candidate> candidates;
        if (list) {
            const int limit = expanded ? 25 : 7;
            for (int i = 0; i < std::min(list->size(), limit); ++i) {
                Candidate item;
                item.label.assign(1, static_cast<char>('A' + i));
                item.text = list->candidate(i).textWithComment("  ").toString();
                item.display = item.label + " " + item.text;
                candidates.push_back(std::move(item));
            }
        }

        const std::string preedit =
            panel.clientPreedit().empty() ? panel.preedit().toString() : panel.clientPreedit().toString();
        return draw(ic, candidates, preedit, expanded, page, list ? list->cursorIndex() : -1,
                    list && list->toPageable() && list->toPageable()->hasPrev(),
                    list && list->toPageable() && list->toPageable()->hasNext());
    }

    void hide() {
        if (!surface_) return;
        wl_surface_attach(surface_, nullptr, 0, 0);
        wl_surface_commit(surface_);
        if (display_) wl_display_flush(display_);
    }

   private:
    static void registryGlobal(void* data, wl_registry* registry, uint32_t name, const char* interface,
                               uint32_t version) {
        auto* self = static_cast<Impl*>(data);
        if (std::strcmp(interface, wl_compositor_interface.name) == 0 && !self->compositor_) {
            self->compositor_ = static_cast<wl_compositor*>(
                wl_registry_bind(registry, name, &wl_compositor_interface, std::min(version, 4u)));
        } else if (std::strcmp(interface, wl_shm_interface.name) == 0 && !self->shm_) {
            self->shm_ = static_cast<wl_shm*>(wl_registry_bind(registry, name, &wl_shm_interface, 1));
        }
    }

    static void registryRemove(void*, wl_registry*, uint32_t) {}

    void setupDisplay(wl_display* display) {
        display_ = display;
        registry_ = wl_display_get_registry(display_);
        static const wl_registry_listener listener = {
            .global = registryGlobal,
            .global_remove = registryRemove,
        };
        wl_registry_add_listener(registry_, &listener, this);
        wl_display_roundtrip(display_);
    }

    void resetSurface() {
        if (popup_) destroyInputPopup(popup_);
        popup_ = nullptr;
        if (surface_) wl_surface_destroy(surface_);
        surface_ = nullptr;
        method_ = nullptr;
    }

    void resetDisplay() {
        resetSurface();
        if (shm_) wl_shm_destroy(shm_);
        shm_ = nullptr;
        if (compositor_) wl_compositor_destroy(compositor_);
        compositor_ = nullptr;
        if (registry_) wl_registry_destroy(registry_);
        registry_ = nullptr;
        display_ = nullptr;
    }

    bool ensureSurface(zwp_input_method_v2* method) {
        if (surface_ && method_ == method) return true;
        resetSurface();
        surface_ = wl_compositor_create_surface(compositor_);
        if (!surface_) return false;
        popup_ = createInputPopup(method, surface_);
        if (!popup_) {
            resetSurface();
            return false;
        }
        method_ = method;
        return true;
    }

    ShmBuffer* newBuffer(int width, int height) {
        const int stride = width * 4;
        const size_t size = static_cast<size_t>(stride) * height;
        int fd = anonymousFile(size);
        if (fd < 0) return nullptr;
        void* data = mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if (data == MAP_FAILED) {
            close(fd);
            return nullptr;
        }
        auto* pool = wl_shm_create_pool(shm_, fd, static_cast<int>(size));
        auto* buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride, WL_SHM_FORMAT_ARGB8888);
        wl_shm_pool_destroy(pool);
        close(fd);
        if (!buffer) {
            munmap(data, size);
            return nullptr;
        }
        auto* result = new ShmBuffer{buffer, data, size};
        wl_buffer_add_listener(buffer, &kBufferListener, result);
        return result;
    }

    bool draw(fcitx::InputContext* ic, const std::vector<Candidate>& items, const std::string& preedit, bool expanded,
              int page, int cursor, bool hasPrev, bool hasNext) {
        const int scale = std::clamp(static_cast<int>(std::ceil(std::max(1.0, ic->scaleFactor()))), 1, 3);
        cairo_surface_t* measureSurface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1, 1);
        cairo_t* measureContext = cairo_create(measureSurface);

        std::vector<int> itemWidths;
        int widest = 0;
        for (const auto& item : items) {
            int width = measure(measureContext, item.display, 14.0, false).width;
            width = std::clamp(width + 20, 64, 248);
            itemWidths.push_back(width);
            widest = std::max(widest, width);
        }
        const int padding = 10;
        const int gap = 5;
        const int headerHeight = preedit.empty() ? 0 : 31;
        const int footerHeight = 25;
        const int cellHeight = 36;
        int logicalWidth = padding * 2;
        int logicalHeight = padding * 2 + headerHeight + footerHeight;
        if (expanded) {
            logicalWidth += 5 * widest + 4 * gap;
            logicalHeight += 5 * cellHeight + 4 * gap;
        } else {
            for (int width : itemWidths) logicalWidth += width;
            logicalWidth += std::max(0, static_cast<int>(items.size()) - 1) * gap;
            logicalHeight += cellHeight;
        }
        logicalWidth = std::max(logicalWidth, 220);
        logicalHeight = std::max(logicalHeight, 76);
        cairo_destroy(measureContext);
        cairo_surface_destroy(measureSurface);

        const int pixelWidth = logicalWidth * scale;
        const int pixelHeight = logicalHeight * scale;
        auto* buffer = newBuffer(pixelWidth, pixelHeight);
        if (!buffer) return false;
        auto* image = cairo_image_surface_create_for_data(static_cast<unsigned char*>(buffer->data),
                                                          CAIRO_FORMAT_ARGB32, pixelWidth, pixelHeight, pixelWidth * 4);
        auto* cr = cairo_create(image);
        cairo_scale(cr, scale, scale);
        cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
        color(cr, 0, 0, 0, 0);
        cairo_paint(cr);
        cairo_set_operator(cr, CAIRO_OPERATOR_OVER);

        roundedRect(cr, 0.5, 0.5, logicalWidth - 1.0, logicalHeight - 1.0, 10.0);
        color(cr, 0.071, 0.063, 0.051, 0.98);
        cairo_fill_preserve(cr);
        color(cr, 1.0, 0.62, 0.13, 0.85);
        cairo_set_line_width(cr, 1.0);
        cairo_stroke(cr);

        int y = padding;
        if (!preedit.empty()) {
            drawText(cr, preedit, padding + 3, y, logicalWidth - 2 * padding, 15.0, true, false);
            y += headerHeight;
        }

        for (size_t i = 0; i < items.size(); ++i) {
            const int column = expanded ? static_cast<int>(i % 5) : static_cast<int>(i);
            const int row = expanded ? static_cast<int>(i / 5) : 0;
            int x = padding;
            if (expanded) {
                x += column * (widest + gap);
            } else {
                for (int previous = 0; previous < column; ++previous) x += itemWidths[previous] + gap;
            }
            const int width = expanded ? widest : itemWidths[i];
            const int cellY = y + row * (cellHeight + gap);
            const bool selected = static_cast<int>(i) == cursor;
            if (selected) {
                roundedRect(cr, x, cellY, width, cellHeight, 7.0);
                color(cr, 1.0, 0.67, 0.20, 1.0);
                cairo_fill(cr);
            }
            drawText(cr, items[i].display, x + 9, cellY + 8, width - 18, 14.0, selected, selected);
        }

        const int rowsHeight = expanded ? 5 * cellHeight + 4 * gap : cellHeight;
        std::string footer = "CTRL+ENTER  注音原樣輸出";
        if (expanded) {
            footer = "PAGE " + std::to_string(std::max(1, page)) + "   ";
            if (hasPrev) footer += "↑ PREVIOUS   ";
            footer += "CTRL+ENTER  原樣輸出";
            if (hasNext) footer += "   ↓ MORE";
        }
        drawText(cr, footer, padding + 3, y + rowsHeight + 6, logicalWidth - 2 * padding, 10.5, false, false);

        cairo_surface_flush(image);
        cairo_destroy(cr);
        cairo_surface_destroy(image);

        wl_surface_set_buffer_scale(surface_, scale);
        wl_surface_attach(surface_, buffer->buffer, 0, 0);
        wl_surface_damage_buffer(surface_, 0, 0, pixelWidth, pixelHeight);
        wl_surface_commit(surface_);
        wl_display_flush(display_);
        return true;
    }

    fcitx::Instance* instance_;
    wl_display* display_ = nullptr;
    wl_registry* registry_ = nullptr;
    wl_compositor* compositor_ = nullptr;
    wl_shm* shm_ = nullptr;
    zwp_input_method_v2* method_ = nullptr;
    wl_surface* surface_ = nullptr;
    zwp_input_popup_surface_v2* popup_ = nullptr;
    std::unique_ptr<fcitx::HandlerTableEntry<fcitx::WaylandConnectionCreated>> connectionCreated_;
    std::unique_ptr<fcitx::HandlerTableEntry<fcitx::WaylandConnectionClosed>> connectionClosed_;
};

NativeCandidatePopup::NativeCandidatePopup(fcitx::Instance* instance) : impl_(std::make_unique<Impl>(instance)) {}

NativeCandidatePopup::~NativeCandidatePopup() = default;

bool NativeCandidatePopup::render(fcitx::InputContext* ic, bool expanded, int page) {
    return impl_->render(ic, expanded, page);
}

void NativeCandidatePopup::hide() { impl_->hide(); }
