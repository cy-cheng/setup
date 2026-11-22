#!/bin/bash
# Fonts for the Nixie shell. Run as your normal user: bash fonts-setup.sh
#   Unbounded (UI font)         -> not packaged; downloaded from google/fonts into ~/.local/share/fonts
#   Material Symbols Rounded    -> icons, official repo package
#   BO NX / TT Chocolates       -> Nixie meter fonts; copied from the arch machine (not redistributable)
set -euo pipefail
if [ "$EUID" -eq 0 ]; then echo "Run as your normal user" >&2; exit 1; fi

yay -S --needed ttf-material-symbols-variable

d="$HOME/.local/share/fonts/unbounded"
mkdir -p "$d"
curl -fsSL -o "$d/Unbounded.ttf" \
  "https://raw.githubusercontent.com/google/fonts/main/ofl/unbounded/Unbounded%5Bwght%5D.ttf"
curl -fsSL -o "$d/OFL.txt" "https://raw.githubusercontent.com/google/fonts/main/ofl/unbounded/OFL.txt"

# Trial fonts from the font specimen are no longer needed once the above exist.
[ -d "$HOME/.local/share/fonts/specimen" ] && gio trash "$HOME/.local/share/fonts/specimen"
fc-cache -f "$HOME/.local/share/fonts" >/dev/null
fc-match "Unbounded"; fc-match "Material Symbols Rounded"
