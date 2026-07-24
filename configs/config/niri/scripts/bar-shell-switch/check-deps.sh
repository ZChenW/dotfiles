#!/usr/bin/env bash
set -Eeuo pipefail

missing=()

check_cmd() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        printf '  OK      %-24s %s\n' "$cmd" "$(command -v "$cmd")"
    else
        printf '  MISSING %-24s\n' "$cmd"
        missing+=("$cmd")
    fi
}

check_font() {
    local family="$1"
    local matched
    matched="$(fc-match "$family" 2>/dev/null || true)"
    if [[ "$matched" == *"$family"* ]]; then
        printf '  OK      font %-19s %s\n' "$family" "$matched"
    else
        printf '  MISSING font %-19s fallback: %s\n' "$family" "${matched:-none}"
        missing+=("font:$family")
    fi
}

echo "Dependency check. This script does not install anything."
echo
echo "Switch scripts:"
for cmd in bash pgrep pkill setsid niri waybar notify-send; do
    check_cmd "$cmd"
done

echo
echo "Caelestia shell runtime:"
for cmd in qs quickshell caelestia caelestia-shell app2unit ddcutil brightnessctl cava nmcli fish qalc swappy wl-copy; do
    check_cmd "$cmd"
done

echo
echo "Waybar helper commands used by the current config:"
for cmd in grim slurp wl-paste wf-recorder ffmpeg magick fuzzel kitty bluetui nmtui nm-connection-editor wpctl pactl pavucontrol wlogout swaylock checkupdates hyprpicker waypaper rfkill; do
    check_cmd "$cmd"
done

echo
echo "Caelestia fonts:"
check_font "Material Symbols Rounded"
check_font "CaskaydiaCove NF"
check_font "Rubik"

echo
if ((${#missing[@]} == 0)); then
    echo "No missing commands/fonts detected by this script."
else
    echo "Missing items detected: ${missing[*]}"
fi

echo
echo "Arch/AUR install suggestions only; review before running manually:"
echo "  yay -S caelestia-shell app2unit fish libqalculate ttf-rubik ttf-cascadia-code-nerd ttf-material-symbols-variable-git"
echo "  sudo pacman -S waybar niri ddcutil brightnessctl cava networkmanager bluez-utils grim slurp wl-clipboard wf-recorder ffmpeg imagemagick fuzzel kitty pavucontrol wlogout swaylock pacman-contrib"
echo
echo "Notes:"
echo "  - caelestia-shell or caelestia-shell-git is the preferred Caelestia install path."
echo "  - Package names can vary by repo/AUR state; this script intentionally does not run sudo."
