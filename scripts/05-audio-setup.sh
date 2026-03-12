#!/usr/bin/env bash
# scripts/05-audio-setup.sh — Deploy audio configs and configure system audio
#
# Idempotent: safe to re-run. Each step checks current state before acting.
#
# What this script does:
#   1. Verifies rodecaster-duo-pipewire AUR package and virtual sinks
#   2. Creates realtime group with limits.d config and adds user to group
#   3. Deploys PipeWire configs (quantum, default devices)
#   4. Deploys WirePlumber config (disable Radeon iGPU HDMI audio)
#   5. Deploys Firefox audio environment variables
#   6. Installs RODECaster udev rule (sudo)
#   7. Installs Plex systemd override (sudo)
#   8. Enables avahi-daemon
#   9. Restarts PipeWire stack
#
# Prerequisites:
#   - rodecaster-duo-pipewire AUR package installed (scripts/02-gaming-setup.sh)
#   - plugdev group created (scripts/02-gaming-setup.sh)
#   - Fill in CHANGEME_ variables below before running
set -euo pipefail
# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

# ---------------------------------------------------------------------------
# CHANGEME_ variables — fill these in before running the script
# ---------------------------------------------------------------------------

CHANGEME_RODECASTER_SERIAL="CHANGEME_RODECASTER_SERIAL"
CHANGEME_USERNAME="CHANGEME_USERNAME"

# ---------------------------------------------------------------------------
# Script internals — do not edit below this line
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --- Guards ---

[[ "$EUID" -eq 0 ]] && error "Do not run as root. The script uses sudo where needed."

if [[ "${CHANGEME_RODECASTER_SERIAL}" == "CHANGEME_RODECASTER_SERIAL" ]]; then
    error "Fill in CHANGEME_RODECASTER_SERIAL with your device serial number.
Find it with: pactl list sources short | grep RODECaster
Example: XXXXXXXXXXX"
fi

if [[ "${CHANGEME_USERNAME}" == "CHANGEME_USERNAME" ]]; then
    error "Fill in CHANGEME_USERNAME with your Linux username.
Example: youruser"
fi

# ---------------------------------------------------------------------------
# Step functions
# ---------------------------------------------------------------------------

step_verify_aur_package() {
    step "Verifying rodecaster-duo-pipewire is installed..."
    if ! pacman -Qi rodecaster-duo-pipewire &>/dev/null; then
        error "rodecaster-duo-pipewire is not installed.
Install it with: yay -S rodecaster-duo-pipewire
Then connect your RODECaster Duo and run:
  rodecaster-duo-set-pro-audio
  rodecaster-duo-pipewire-install
  systemctl --user restart pipewire pipewire-pulse wireplumber"
    fi
    ok "rodecaster-duo-pipewire is installed."

    if ! wpctl status 2>/dev/null | grep -q "rcp_duo_system_in"; then
        error "RODECaster virtual sinks not found in wpctl status.
Connect your RODECaster Duo and run:
  rodecaster-duo-set-pro-audio
  rodecaster-duo-pipewire-install
  systemctl --user restart pipewire pipewire-pulse wireplumber
Then verify with: wpctl status | grep rcp_duo"
    fi
    ok "RODECaster virtual sinks present (rcp_duo_system_in found)."
}

step_realtime_group() {
    step "Setting up realtime audio group..."
    if ! getent group realtime &>/dev/null; then
        sudo groupadd realtime
        ok "Created group: realtime"
    else
        ok "Group exists: realtime"
    fi

    sudo tee /etc/security/limits.d/99-realtime.conf > /dev/null << 'EOF'
@realtime - rtprio 99
@realtime - nice -20
@realtime - memlock unlimited
EOF
    ok "Wrote /etc/security/limits.d/99-realtime.conf"

    if id -nG "${CHANGEME_USERNAME}" | grep -qw realtime; then
        ok "${CHANGEME_USERNAME} already in realtime group."
    else
        sudo usermod -aG realtime "${CHANGEME_USERNAME}"
        ok "Added ${CHANGEME_USERNAME} to realtime group."
        warn "Log out and back in for realtime group membership to take effect."
        _realtime_group_changed=1
    fi
}

step_pipewire_configs() {
    step "Deploying PipeWire configs..."
    local pipewire_conf_d="${HOME}/.config/pipewire/pipewire.conf.d"
    mkdir -p "${pipewire_conf_d}"

    # 99-quantum.conf — deploy as-is (no CHANGEME_ substitution needed)
    local quantum_src="${REPO_ROOT}/configs/audio/99-quantum.conf.example"
    local quantum_dst="${pipewire_conf_d}/99-quantum.conf"
    if [[ ! -f "${quantum_dst}" ]]; then
        cp "${quantum_src}" "${quantum_dst}"
        ok "Deployed: ${quantum_dst}"
    else
        ok "Already exists: ${quantum_dst}"
    fi

    # default-devices.conf — substitute CHANGEME_RODECASTER_SERIAL
    local devices_src="${REPO_ROOT}/configs/audio/default-devices.conf.example"
    local devices_dst="${pipewire_conf_d}/default-devices.conf"
    if [[ ! -f "${devices_dst}" ]]; then
        sed "s/CHANGEME_RODECASTER_SERIAL/${CHANGEME_RODECASTER_SERIAL}/g" \
            "${devices_src}" > "${devices_dst}"
        ok "Deployed: ${devices_dst} (serial: ${CHANGEME_RODECASTER_SERIAL})"
    else
        ok "Already exists: ${devices_dst}"
    fi

    # NOTE: 99-rodecaster-duo-virtual-sinks.conf.example is documentation only.
    # The AUR package generates the actual virtual sink config. Do NOT deploy it.
    info "Skipping 99-rodecaster-duo-virtual-sinks — generated by AUR package, not deployed."
    info "Verify sinks with: wpctl status | grep rcp_duo"
}

step_wireplumber_config() {
    step "Deploying WirePlumber config..."
    local wp_conf_d="${HOME}/.config/wireplumber/wireplumber.conf.d"
    mkdir -p "${wp_conf_d}"

    local src="${REPO_ROOT}/configs/audio/51-disable-radeon-hdmi-audio.conf.example"
    local dst="${wp_conf_d}/51-disable-radeon-hdmi-audio.conf"
    if [[ ! -f "${dst}" ]]; then
        cp "${src}" "${dst}"
        ok "Deployed: ${dst}"
        warn "IMPORTANT: Edit ${dst} and adjust device.name for your hardware."
        warn "Find your device with: wpctl status | grep -i hdmi"
    else
        ok "Already exists: ${dst}"
    fi
}

step_environment_config() {
    step "Deploying Firefox audio environment config..."
    local env_d="${HOME}/.config/environment.d"
    mkdir -p "${env_d}"

    local src="${REPO_ROOT}/configs/audio/firefox-audio.conf.example"
    local dst="${env_d}/firefox-audio.conf"
    if [[ ! -f "${dst}" ]]; then
        cp "${src}" "${dst}"
        ok "Deployed: ${dst}"
        info "Firefox audio env vars take effect on next login."
    else
        ok "Already exists: ${dst}"
    fi
}

step_udev_rule() {
    step "Installing RODECaster udev rule..."
    local src="${REPO_ROOT}/configs/audio/99-rodecaster.rules.example"
    local dst="/etc/udev/rules.d/99-rodecaster.rules"
    if [[ ! -f "${dst}" ]]; then
        sudo cp "${src}" "${dst}"
        sudo udevadm control --reload-rules
        ok "Installed udev rule: ${dst}"
        info "Reconnect RODECaster Duo for udev rule to take effect on the device."
    else
        ok "Already exists: ${dst}"
    fi
}

step_plex_override() {
    step "Installing Plex Media Server systemd override..."
    local override_dir="/etc/systemd/system/plexmediaserver.service.d"
    local src="${REPO_ROOT}/configs/audio/plexmediaserver-override.conf.example"
    local dst="${override_dir}/override.conf"
    sudo mkdir -p "${override_dir}"
    if [[ ! -f "${dst}" ]]; then
        sudo cp "${src}" "${dst}"
        sudo systemctl daemon-reload
        ok "Installed Plex override: ${dst}"
        info "Plex will now wait for /mnt/CHANGEME_MEDIA_MOUNT to mount before starting."
    else
        ok "Already exists: ${dst}"
    fi
}

step_avahi() {
    step "Enabling avahi-daemon..."
    if systemctl is-active --quiet avahi-daemon; then
        ok "avahi-daemon is already active."
    else
        sudo systemctl enable --now avahi-daemon
        ok "Enabled and started avahi-daemon."
    fi
}

step_restart_audio() {
    step "Restarting PipeWire stack..."
    systemctl --user restart pipewire pipewire-pulse wireplumber
    ok "Restarted: pipewire, pipewire-pulse, wireplumber"
    info "Audio config changes are now active."
}

# ---------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------

_realtime_group_changed=0

step_verify_aur_package
step_realtime_group
step_pipewire_configs
step_wireplumber_config
step_environment_config
step_udev_rule
step_plex_override
step_avahi
step_restart_audio

info "---"
info "Audio setup complete."
info ""
info "Next steps:"
info "1. Edit ~/.config/wireplumber/wireplumber.conf.d/51-disable-radeon-hdmi-audio.conf"
info "   and adjust device.name for your hardware."
info "   Find your Radeon HDMI device with: wpctl status | grep -i hdmi"
info ""
info "2. Test per-app audio routing:"
info "   - Steam, games, browser, Spotify → System channel (default sink)"
info "   - Discord, OBS → set output to Chat channel (rcp_duo_chat_in)"
info ""
info "3. See docs/05-audio.md for full audio setup guide and troubleshooting."

if [[ "${_realtime_group_changed}" -eq 1 ]]; then
    warn ""
    warn "REMINDER: Log out and back in for realtime group membership to take effect."
    warn "PipeWire needs the realtime group for low-latency audio processing."
fi
