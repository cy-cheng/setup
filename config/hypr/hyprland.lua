-- Migrated from ~/.config/hypr/hyprland.conf for Hyprland 0.55+
-- Main config location: ~/.config/hypr/hyprland.lua

local terminal = "kitty"
local fileManager = "thunar"
local menu = "rofi -show drun"
local mainMod = "SUPER"

-- Monitors and their default workspaces.
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 1.25 })
hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "auto", scale = 1 })
hl.workspace_rule({ workspace = "1", monitor = "eDP-1", default = true })
hl.workspace_rule({ workspace = "2", monitor = "HDMI-A-1", default = true })

-- Session services. Hyprland.start has exec-once semantics.
hl.on("hyprland.start", function()
    hl.exec_cmd("hypridle")
    hl.exec_cmd("hyprsunset")
    hl.exec_cmd("onedrive -m")
    hl.exec_cmd("dunst")
    hl.exec_cmd([[env LC_TIME="en_GB.UTF-8" /home/brine/.config/nixie-shell/start-ui.sh]])
    hl.exec_cmd("nm-applet")
    hl.exec_cmd("/usr/bin/input-remapper-control --command autoload")
    hl.exec_cmd("gnome-keyring-daemon --start")
end)

hl.env("GDK_SCALE", "2")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_SCALE_FACTOR", "1.5")

hl.config({
    general = {
        gaps_in = 5,
        gaps_out = 7,
        border_size = 2,
        col = {
            active_border = { colors = { "rgba(ffb83eee)", "rgba(ff9d1fee)" }, angle = 45 },
            inactive_border = "rgba(7b2d06aa)",
        },
        resize_on_border = false,
        allow_tearing = false,
        layout = "dwindle",
    },
    decoration = {
        rounding = 4,
        rounding_power = 2,
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        shadow = {
            enabled = true,
            range = 4,
            render_power = 3,
            color = "rgba(1a1a1aee)",
        },
        blur = {
            enabled = true,
            size = 8,
            passes = 3,
            noise = 0.0,
            vibrancy = 0.1696,
        },
    },
    animations = { enabled = true },
    dwindle = { preserve_split = true },
    master = { new_status = "master" },
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo = true,
    },
    input = {
        kb_layout = "us",
        kb_variant = "",
        kb_model = "",
        kb_options = "",
        kb_rules = "",
        follow_mouse = 1,
        sensitivity = 0.3,
        touchpad = {
            scroll_factor = 1.0,
            natural_scroll = true,
        },
    },
    binds = { allow_workspace_cycles = true },
    xwayland = { force_zero_scaling = true },
})

hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
    workspace_name = "e + 1",
})

hl.device({ name = "epic-mouse-v1", sensitivity = -0.5 })

hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + Delete", hl.dsp.exit())
hl.bind(mainMod .. " + M", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind("Print", hl.dsp.exec_cmd("hyprshot -m region -z --output-folder ~/Pictures/Screenshots"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("~/.local/bin/hypr-code-ocr"))

hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))

for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + Tab", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + SHIFT + Tab", hl.dsp.focus({ workspace = "e-1" }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + ALT + mouse:272", hl.dsp.window.resize(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

local lockSession = "/home/brine/.config/hypr/scripts/lock-session.sh"
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd(lockSession), { locked = true })
hl.bind(mainMod .. " + equal", hl.dsp.exec_cmd(lockSession))

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- Keep the original catch-all rules from the pre-Lua config.
hl.window_rule({ name = "catch-all", match = { class = ".*" } })
hl.layer_rule({ name = "layer", no_anim = true })
hl.layer_rule({
    name = "blur-nixie-popups",
    match = { namespace = "^nixie-(calendar|llm|notifications|candidates|network-menu)$" },
    blur = true,
    ignore_alpha = 0.12,
    no_anim = true,
})
hl.layer_rule({
    name = "blur-nixie-tooltips",
    match = { namespace = "^nixie-shell$" },
    blur_popups = true,
    no_anim = true,
})
hl.layer_rule({
    name = "blur-nixie-desktop",
    match = { namespace = "^nixie-desktop$" },
    blur = true,
    ignore_alpha = 0.12,
    no_anim = true,
})
