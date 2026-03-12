#!/usr/bin/env bash
# scripts/lib/common.sh — shared helpers for all setup scripts
#
# Usage: source this file at the top of each setup script:
#   # shellcheck source=lib/common.sh
#   . "$(dirname "$0")/lib/common.sh"
#
# Note: Do NOT add 'set -euo pipefail' here — this file is sourced,
# so the sourcing script must set those options.

# Colors
readonly _RED='\033[0;31m'
readonly _GREEN='\033[0;32m'
readonly _YELLOW='\033[1;33m'
readonly _BLUE='\033[0;34m'
readonly _NC='\033[0m'  # reset

info()  { echo -e "${_GREEN}[INFO]${_NC}  $*"; }
warn()  { echo -e "${_YELLOW}[WARN]${_NC}  $*"; }
error() { echo -e "${_RED}[ERROR]${_NC} $*" >&2; exit 1; }
step()  { echo -e "${_BLUE}[STEP]${_NC}  $*"; }
ok()    { echo -e "${_GREEN}[OK]${_NC}    $*"; }

# Idempotency helpers

dir_exists_or_create() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        ok "Directory exists: $dir"
    else
        mkdir -p "$dir"
        ok "Created: $dir"
    fi
}

file_exists_or_copy() {
    local src="$1" dst="$2"
    if [[ -f "$dst" ]]; then
        ok "File exists: $dst"
    else
        cp "$src" "$dst"
        ok "Copied $src -> $dst"
    fi
}

# Package helpers

pacman_install_if_missing() {
    local pkg="$1"
    if pacman -Qi "$pkg" &>/dev/null; then
        ok "Already installed: $pkg"
    else
        info "Installing: $pkg"
        sudo pacman -S --noconfirm "$pkg"
    fi
}

yay_install_if_missing() {
    local pkg="$1"
    if pacman -Qi "$pkg" &>/dev/null; then
        ok "Already installed: $pkg"
    else
        info "Installing (AUR): $pkg"
        yay -S --noconfirm "$pkg"
    fi
}
