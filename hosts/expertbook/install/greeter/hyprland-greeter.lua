-- Minimal Hyprland session that only shows the ReGreet login screen.
-- Installed to /etc/greetd/hyprland-greeter.lua by ~/greeter-setup.sh

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 2 })

hl.config({
    misc = {
        disable_hyprland_logo = true,
        force_default_wallpaper = 0,
        background_color = 0xff070605,
    },
    animations = { enabled = false },
    -- Plain sRGB output: with colour management on, this panel showed washed-out,
    -- lavender-tinted colours and ghosted text on the login screen.
    render = { cm_enabled = false },
    -- The greeter user has no writable home: never show update news or nags.
    ecosystem = { no_update_news = true, no_donation_nag = true },
    input = {
        kb_layout = "us",
        touchpad = { natural_scroll = true },
    },
})

hl.on("hyprland.start", function ()
    -- When ReGreet exits (login succeeded), leave so greetd can start the real session.
    hl.exec_cmd("regreet; hyprctl dispatch 'hl.dsp.exit()'")
end)
