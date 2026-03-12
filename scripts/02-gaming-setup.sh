#!/usr/bin/env bash
# scripts/02-gaming-setup.sh — Install gaming packages and apply performance config
#
# Idempotent: safe to re-run. Each step checks current state before acting.
# Prerequisites: yay (AUR helper) must be installed.
#
# What this script does:
#   1. Installs pacman and AUR gaming packages
#   2. Creates /mnt/<GAMING_MOUNT>/SteamLibrary with correct ownership
#   3. Adds the current user to audio and plugdev groups
#   4. Disables ananicy-cpp (conflicts with gamemode)
#   5. Writes shader cache config to ~/.config/environment.d/gaming.conf
set -euo pipefail
# shellcheck source=lib/common.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/lib/common.sh"

# ---------------------------------------------------------------------------
# CHANGEME_ variables — fill these in before running the script
# ---------------------------------------------------------------------------

GAMING_MOUNT="CHANGEME_GAMING_MOUNT"

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------

if [[ "${GAMING_MOUNT}" == "CHANGEME_GAMING_MOUNT" ]]; then
    error "Fill in GAMING_MOUNT with your gaming drive mount point name.\nFind it with: lsblk -o NAME,LABEL,MOUNTPOINT\nExample: games"
fi

# --- Package arrays ---

PACMAN_PKGS=(
    # Steam & core gaming platform
    steam               # Valve game platform
    lutris              # Game launcher for non-Steam games (Battle.net, etc.)

    # Performance tools
    gamemode            # CPU/GPU boost while gaming (D-Bus activated — no service management needed)
    lib32-gamemode      # 32-bit game support for gamemode
    mangohud            # In-game FPS/GPU/CPU performance overlay
    lib32-mangohud      # 32-bit game support for mangohud

    # Filesystem / media
    exfatprogs          # exFAT filesystem support (USB drives, external media)

    # OBS — CachyOS patched build — do NOT install alongside obs-studio
    obs-studio-browser  # OBS with browser source (CachyOS build, conflicts with obs-studio)
)

AUR_PKGS=(
    protonplus              # GUI: install GE-Proton, Proton-CachyOS runners
    cachyos-gaming-meta     # Meta: wine, umu-launcher, proton-cachyos-slr, codecs
    rusty-path-of-building  # PoE1+2 build planner, native — no Wine required
)

# --- Check yay is available ---

if ! command -v yay &>/dev/null; then
    error "yay not found. Install yay (AUR helper) before running this script."
fi

# --- Install packages ---

step "Installing pacman packages..."
for pkg in "${PACMAN_PKGS[@]}"; do
    pacman_install_if_missing "$pkg"
done

step "Installing AUR packages..."
for pkg in "${AUR_PKGS[@]}"; do
    yay_install_if_missing "$pkg"
done

# --- Steam library directory ---

step "Setting up Steam library directory..."
if ! mountpoint -q "/mnt/${GAMING_MOUNT}" 2>/dev/null; then
    warn "/mnt/${GAMING_MOUNT} is not mounted — skipping SteamLibrary creation. Mount the gaming drive and re-run."
else
    if [[ ! -d "/mnt/${GAMING_MOUNT}/SteamLibrary" ]]; then
        sudo mkdir -p "/mnt/${GAMING_MOUNT}/SteamLibrary"
        sudo chown "${USER}:${USER}" "/mnt/${GAMING_MOUNT}/SteamLibrary"
        ok "Created /mnt/${GAMING_MOUNT}/SteamLibrary (owned by ${USER})"
    else
        # Check ownership
        _owner=$(stat -c '%U' "/mnt/${GAMING_MOUNT}/SteamLibrary")
        if [[ "$_owner" == "${USER}" ]]; then
            ok "Steam library directory already exists: /mnt/${GAMING_MOUNT}/SteamLibrary"
        else
            warn "/mnt/${GAMING_MOUNT}/SteamLibrary exists but is owned by '$_owner', not '${USER}'. Fix with: sudo chown ${USER}:${USER} /mnt/${GAMING_MOUNT}/SteamLibrary"
        fi
    fi
fi

# --- Group membership ---

step "Configuring group membership..."

_groups_changed=0

add_user_to_group() {
    local group="$1"
    # Create group if it doesn't exist (plugdev is not standard on Arch/CachyOS)
    if ! getent group "$group" &>/dev/null; then
        sudo groupadd "$group"
        info "Created group: $group"
    fi
    if groups "${USER}" | grep -qw "$group"; then
        ok "Already in group: $group"
    else
        sudo usermod -aG "$group" "${USER}"
        ok "Added ${USER} to group: $group"
        _groups_changed=1
    fi
}

add_user_to_group audio
add_user_to_group plugdev

if [[ "$_groups_changed" -eq 1 ]]; then
    warn "Log out and back in for group changes to take effect."
fi

# --- Disable ananicy-cpp (conflicts with gamemode) ---

step "Checking ananicy-cpp service..."
if systemctl is-enabled ananicy-cpp &>/dev/null; then
    sudo systemctl stop ananicy-cpp
    sudo systemctl disable ananicy-cpp
    ok "Disabled ananicy-cpp (conflicts with gamemode)"
else
    ok "ananicy-cpp already disabled"
fi

# Note: gamemode is D-Bus/socket activated automatically when a game launches via
# gamemoderun or game-performance. Do NOT attempt 'systemctl enable gamemode'.

# --- Shader cache config ---

step "Writing shader cache config..."
mkdir -p "${HOME}/.config/environment.d"
GAMING_CONF="${HOME}/.config/environment.d/gaming.conf"
if [[ ! -f "${GAMING_CONF}" ]]; then
    cp "${SCRIPT_DIR}/../configs/gaming/gaming.conf.example" "${GAMING_CONF}"
    ok "Wrote shader cache config: ${GAMING_CONF}"
    info "Changes take effect on next login."
else
    ok "Shader cache config already exists: ${GAMING_CONF}"
fi

# --- Summary ---

info "---"
info "Gaming setup complete. Next steps:"
info ""
info "1. Launch ProtonPlus and install Proton runners (GE-Proton, Proton-CachyOS)."
info "   See docs/02-gaming.md for the recommended runner for each use case."
info ""
info "2. Open Steam -> Settings -> Storage -> Add Library Folder -> /mnt/${GAMING_MOUNT}/SteamLibrary"
info "   (Only if /mnt/${GAMING_MOUNT} was mounted and SteamLibrary was created above.)"
info ""
info "3. See docs/02-gaming.md for:"
info "   - Steam launch options (game-performance, mangohud, DLSS, anti-cheat)"
info "   - Proton version guide (which runner for which game)"
if [[ "$_groups_changed" -eq 1 ]]; then
    warn "REMINDER: Log out and back in for group changes (audio, plugdev) to take effect."
fi
