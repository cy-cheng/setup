# config.fish — ported from the arch machine, cleaned up.
# Dropped: hardcoded AWS credentials, `nvm use latest` on every start (system
# node is used now), hand-started ssh-agent (systemd runs one), vim -> uv alias.

fish_add_path -g ~/.local/bin ~/.cargo/bin

set -gx EDITOR nvim
set -gx VISUAL nvim

# One ssh-agent per login, started by systemd (ssh-agent.socket).
if not set -q SSH_AUTH_SOCK; and test -S $XDG_RUNTIME_DIR/ssh-agent.socket
    set -gx SSH_AUTH_SOCK $XDG_RUNTIME_DIR/ssh-agent.socket
end

if status is-interactive
    set -g fish_greeting # no welcome banner

    abbr -a vim nvim
    abbr -a v nvim
    abbr -a rm rm-to-trash # `command rm` for a real rm
    alias venv "source .venv/bin/activate.fish"

    # kitty extras, only inside kitty
    if test "$TERM" = xterm-kitty
        alias ssh "kitten ssh" # copies kitty's terminfo to the remote
        alias view "kitty +kitten icat"
    end

    # `cd` learns your directories (zoxide); `cdi` picks one interactively
    type -q zoxide; and zoxide init fish --cmd cd | source
    # Ctrl-R history, Ctrl-T files, Alt-C dirs
    type -q fzf; and fzf --fish | source
end
