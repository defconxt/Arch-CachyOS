#!/usr/bin/env bash
# dcs-env.sh — Shared DCS World environment variables
# Sourced by both 04-dcs-launch.sh and 04-dcs-launch-vr.sh to prevent drift.

# --- Runner ---
export WINEPREFIX="$PREFIX"
export PROTONPATH="$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton10-32"
export GAMEID="umu-dcs-world"

# --- Display ---
export PROTON_ENABLE_WAYLAND=0

# --- Input ---
# Prevents HOTAS registering twice (joydev + HIDAPI = phantom duplicate in DCS)
export SDL_JOYSTICK_HIDAPI=0

# --- Wine ---
# wbemprox=n   suppress WMI spam in log
# NPClient64=b TrackIR 64-bit bridge (LinuxTrack)
# NPClient=b   TrackIR 32-bit bridge
# FreeTrackClient=b  FreeTrack protocol fallback
export WINEDLLOVERRIDES='wbemprox=n;NPClient64=b;NPClient=b;FreeTrackClient=b'

# Required for DCS writing to btrfs COW paths without permission errors
export WINE_SIMULATE_WRITECOPY=1
