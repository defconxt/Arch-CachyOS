#!/usr/bin/env bash
# 04-dcs-setup.sh — Idempotent DCS World setup for CachyOS
# Run after DCS standalone installer has completed.
# See docs/04-dcs-world.md for full documentation.

set -euo pipefail
# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"

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

# --- Config ---
GAME_USER="${SUDO_USER:-$(whoami)}"
PREFIX="/mnt/${GAMING_MOUNT}/dcs-world"
SAVED_GAMES="$PREFIX/drive_c/users/$GAME_USER/Saved Games"
CFG_DIR="$HOME/.config/dcs-on-linux"
BIN_DIR="$HOME/.local/bin"
PROTON_DIR="$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton10-32"
LINUXTRACK_VERSION="0.99.29"
LINUXTRACK_URL="https://github.com/uglyDwarf/linuxtrack/releases/download/v${LINUXTRACK_VERSION}/linuxtrackx-ir-${LINUXTRACK_VERSION}-x86_64.AppImage"
LINUXTRACK_BIN="$BIN_DIR/linuxtrackx-ir.AppImage"

export WINEPREFIX="$PREFIX"

check_prefix() {
    if [[ ! -d "$PREFIX/drive_c/Program Files/Eagle Dynamics/DCS World" ]]; then
        echo "[ERROR] DCS World not found at $PREFIX"
        echo "        Install DCS Standalone to $PREFIX before running this script."
        exit 1
    fi
}

check_proton() {
    if [[ ! -d "$PROTON_DIR" ]]; then
        echo "[ERROR] GE-Proton10-32 not found at $PROTON_DIR"
        echo "        Install via ProtonPlus before running this script."
        exit 1
    fi
}

# --- Steps ---

step_config_dir() {
    info "Creating launcher config dir..."
    mkdir -p "$CFG_DIR"

    if [[ ! -f "$CFG_DIR/prefix.cfg" ]]; then
        echo "WINEPREFIX=$PREFIX" > "$CFG_DIR/prefix.cfg"
        ok "Created prefix.cfg"
    else
        ok "prefix.cfg already exists"
    fi

    if [[ ! -f "$CFG_DIR/firstrun.cfg" ]]; then
        echo "firstrun=done" > "$CFG_DIR/firstrun.cfg"
        ok "Created firstrun.cfg"
    fi
}

step_winetricks() {
    info "Installing winetricks dependencies..."
    local deps=(d3dcompiler_47 vcrun2022 corefonts xact_x64 dxvk win10 consolas)
    for dep in "${deps[@]}"; do
        info "  winetricks $dep"
        WINEPREFIX="$PREFIX" winetricks -q "$dep" || warn "winetricks $dep may have partially failed — check manually"
    done
    ok "Winetricks dependencies done"
}

step_registry() {
    info "Injecting Wine/VR registry keys (RTX 5090)..."
    local reg_file
    reg_file=$(mktemp /tmp/dcs-vr-XXXXXX.reg)

    cat > "$reg_file" << 'EOF'
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Wine\VR]
"openxr_vulkan_device_vid"=dword:000010de
"openxr_vulkan_device_pid"=dword:00002b85
"state"=dword:00000001
"openxr_runtime"="wivrn"
EOF

    WINEPREFIX="$PREFIX" wine regedit "$reg_file"
    rm -f "$reg_file"
    ok "Registry keys applied"
}

step_symlink() {
    info "Checking Saved Games symlink..."
    local dcs_dir="$SAVED_GAMES/DCS"
    local dcs_world_link="$SAVED_GAMES/DCS World"

    if [[ ! -d "$dcs_dir" ]]; then
        mkdir -p "$dcs_dir"
        info "  Created $dcs_dir"
    fi

    if [[ -L "$dcs_world_link" ]]; then
        ok "Symlink already exists: DCS World -> DCS"
    else
        ln -sf "$dcs_dir" "$dcs_world_link"
        ok "Created symlink: DCS World -> DCS"
    fi
}

step_options_lua() {
    info "Fixing options.lua permissions..."
    local opts="$SAVED_GAMES/DCS/Config/options.lua"
    if [[ -f "$opts" ]]; then
        chmod 644 "$opts"
        ok "options.lua set to 644"
    else
        warn "options.lua not found — will be created on first DCS launch"
    fi
}

step_udev() {
    info "Installing VKB udev rules..."
    local rule_file="/etc/udev/rules.d/40-vkb.rules"

    if [[ -f "$rule_file" ]]; then
        ok "udev rules already installed"
        return
    fi

    echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="231d", MODE="0664", TAG+="uaccess"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="231d", MODE="0664", TAG+="uaccess"' \
        | sudo tee "$rule_file" > /dev/null

    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=usb --attr-match=idVendor=231d
    ok "VKB udev rules installed and applied"
}

step_launch_script() {
    info "Deploying launch script..."
    mkdir -p "$BIN_DIR"
    local script_src
    script_src="$(dirname "$0")/04-dcs-launch.sh"

    if [[ ! -f "$script_src" ]]; then
        warn "04-dcs-launch.sh not found in scripts/ — skipping"
        return
    fi

    cp "$script_src" "$BIN_DIR/launch-dcs.sh"
    chmod +x "$BIN_DIR/launch-dcs.sh"
    ok "launch-dcs.sh deployed to $BIN_DIR"
}

step_desktop_entry() {
    info "Creating desktop entry..."
    local desktop_dir="$HOME/.local/share/applications"
    mkdir -p "$desktop_dir"

    if [[ -f "$desktop_dir/dcs-world.desktop" ]]; then
        ok "Desktop entry already exists — skipping"
        return
    fi

    cat > "$desktop_dir/dcs-world.desktop" << EOF
[Desktop Entry]
Name=DCS World
Comment=Digital Combat Simulator
Exec=$BIN_DIR/launch-dcs.sh -n
Icon=dcs-world
Type=Application
Categories=Game;
EOF
    ok "Desktop entry created"
}

step_launch_script_vr() {
    local src
    src="$(dirname "$0")/04-dcs-launch-vr.sh"
    local dst="$HOME/.local/bin/launch-dcs-vr.sh"
    info "Deploying VR launch script..."
    if [[ ! -f "$src" ]]; then
        error "Source not found: $src — run from repo root or scripts/ directory"
    fi
    dir_exists_or_create "$HOME/.local/bin"
    if [[ -f "$dst" ]]; then
        ok "VR launch script already deployed: $dst"
        return
    fi
    cp "$src" "$dst"
    chmod +x "$dst"
    ok "VR launch script deployed: $dst"
}

step_desktop_entry_vr() {
    local dst="$HOME/.local/share/applications/dcs-world-vr.desktop"
    info "Installing DCS World VR desktop entry..."
    dir_exists_or_create "$HOME/.local/share/applications"
    if [[ -f "$dst" ]]; then
        ok "VR desktop entry already installed: $dst"
        return
    fi
    cat > "$dst" << 'EOF'
[Desktop Entry]
Name=DCS World (VR)
Comment=Digital Combat Simulator - VR Mode (WiVRn + Quest 3)
Exec=launch-dcs-vr.sh -n
Icon=dcs-world
Terminal=false
Type=Application
Categories=Game;
EOF
    ok "VR desktop entry installed: $dst"
}

step_linuxtrack() {
    info "Checking LinuxTrack AppImage..."
    if [[ -x "$LINUXTRACK_BIN" ]]; then
        ok "LinuxTrack already present at $LINUXTRACK_BIN"
        return
    fi

    info "Downloading LinuxTrack v${LINUXTRACK_VERSION}..."
    wget -q --show-progress -O "$LINUXTRACK_BIN" "$LINUXTRACK_URL"

    # Verify download integrity
    EXPECTED_SHA256="CHANGEME_LINUXTRACK_SHA256"  # Update after verifying download
    if [[ "${EXPECTED_SHA256}" != "CHANGEME_LINUXTRACK_SHA256" ]]; then
        echo "$EXPECTED_SHA256  $LINUXTRACK_BIN" | sha256sum --check --quiet || error "LinuxTrack checksum mismatch — download may be corrupted"
    fi

    chmod +x "$LINUXTRACK_BIN"
    ok "LinuxTrack downloaded"

    info "Installing Wine bridge into DCS prefix..."
    WINEPREFIX="$PREFIX" "$LINUXTRACK_BIN" --install-wine-bridge
    ok "LinuxTrack Wine bridge installed"

    cat > "$HOME/.local/share/applications/linuxtrackx-ir.desktop" << EOF
[Desktop Entry]
Name=LinuxTrack
Comment=TrackIR bridge for Linux
Exec=$LINUXTRACK_BIN
Icon=linuxtrack
Type=Application
Categories=Game;
EOF
    ok "LinuxTrack desktop entry created"
}

# --- Main ---
main() {
    echo "=== DCS World Setup ==="
    echo "Prefix: $PREFIX"
    echo "User:   $GAME_USER"
    echo ""

    check_prefix
    check_proton

    step_config_dir
    step_winetricks
    step_registry
    step_symlink
    step_options_lua
    step_udev
    step_launch_script
    step_desktop_entry
    step_launch_script_vr
    step_desktop_entry_vr
    step_linuxtrack

    echo ""
    echo "=== Setup complete ==="
    echo ""
    echo "Next steps:"
    echo "  1. Connect VKB HOTAS and replug (udev rules now active)"
    echo "  2. Start LinuxTrack, click Start Tracking"
    echo "  3. Launch DCS: ~/.local/bin/launch-dcs.sh -n"
    echo "  4. Migrate F-18C keybinds per dcs-world.md GUID table"
}

main "$@"
