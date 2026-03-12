# Audio Setup

This guide covers audio routing on CachyOS with PipeWire, WirePlumber, and the
RODECaster Duo. It documents the configuration that `scripts/05-audio-setup.sh`
deploys and provides the per-app routing reference you will consult when configuring
Discord and OBS.

## Overview

Audio flows through PipeWire with WirePlumber managing device policy. The RODECaster
Duo runs in **Pro Audio** mode, which creates two virtual input channels exposed as
PipeWire sinks:

- **System** (`rcp_duo_system_in`) — default sink; receives all program audio
- **Chat** (`rcp_duo_chat_in`) — communication sink; receives Discord and OBS

The RODECaster Duo's onboard DSP (noise gate, compressor, APHEX processing) handles
mic audio quality. No software noise suppression (RNNoise or similar) is needed or
configured.

`scripts/05-audio-setup.sh` handles deploying all config files, setting up the
realtime audio group, configuring the Plex Media Server systemd override, and
enabling Avahi.

---

## Prerequisites

- `rodecaster-duo-pipewire` AUR package installed (handled by `scripts/02-gaming-setup.sh`)
- RODECaster Duo connected via USB and **Pro Audio** profile activated on the device
- `plugdev` group membership (added by `scripts/02-gaming-setup.sh`)

---

## Quick Setup

Fill in the two variables at the top of the script before running it:

- `CHANGEME_RODECASTER_SERIAL` — your device's serial number
- `CHANGEME_USERNAME` — your Linux username (shown by running `whoami`)

**Find your RODECaster serial:**

```bash
pactl list sources short | grep RODECaster
```

The serial appears in the source name, for example: `alsa_input.usb-R__DE_RODECaster_Duo_XXXXXXXXXXX-00.analog-stereo`

Then run the script:

```bash
bash scripts/05-audio-setup.sh
```

The script deploys all configs, creates the realtime group, restarts PipeWire services,
copies the Plex systemd override, and enables Avahi. Log out and back in after the
script completes for the realtime group to take effect.

---

## 1. Config File Index

All audio configs ship as `.example` files in `configs/audio/`. The script copies
these to the correct system paths with any `CHANGEME_` substitutions applied.

| File | Purpose | Destination Path |
|------|---------|-----------------|
| `99-quantum.conf.example` | PipeWire clock/quantum (Firefox dropout fix) | `~/.config/pipewire/pipewire.conf.d/` |
| `99-rodecaster-duo-virtual-sinks.conf.example` | Reference only — documents virtual sinks created by AUR package | (reference only, not deployed) |
| `default-devices.conf.example` | Sets default PipeWire sink and source | `~/.config/pipewire/pipewire.conf.d/` |
| `51-disable-radeon-hdmi-audio.conf.example` | WirePlumber rule: disables Radeon iGPU HDMI audio | `~/.config/wireplumber/wireplumber.conf.d/` |
| `firefox-audio.conf.example` | Environment variables for Firefox PipeWire/Wayland | `~/.config/environment.d/` |
| `99-rodecaster.rules.example` | udev rule: plugdev group access to RODECaster HID | `/etc/udev/rules.d/` (requires sudo) |
| `plexmediaserver-override.conf.example` | systemd drop-in: Plex waits for /mnt/media mount | `/etc/systemd/system/plexmediaserver.service.d/` (requires sudo) |

---

## 2. Virtual Sink Architecture

When `rodecaster-duo-pipewire` is installed and Pro Audio mode is activated, the AUR
package generates WirePlumber config that creates two virtual sinks:

```
Application audio
      │
      ├─── rcp_duo_system_in  (System sink — default)
      │         │
      │         └─── RODECaster Duo AUX0/AUX1 pair (main program mix channel)
      │
      └─── rcp_duo_chat_in   (Chat sink — manual routing required)
                │
                └─── RODECaster Duo FL/FR pair (voice chat channel)
```

The System sink is set as the PipeWire default, so all apps route there automatically
unless explicitly assigned elsewhere. Only communication apps (Discord, OBS) need
manual sink selection.

Verify the virtual sinks are present after setup:

```bash
wpctl status | grep rcp_duo
```

---

## 3. Per-App Audio Routing

| Application | Target Sink | How to Set |
|-------------|------------|------------|
| Steam | System | Default — no action needed |
| Games | System | Default — no action needed |
| Browser | System | Default — no action needed |
| Spotify | System | Default — no action needed |
| Discord | Chat | **Discord Settings** -> **Voice & Video** -> **Output Device** -> `rcp_duo_chat_in` |
| OBS | Chat | **OBS Settings** -> **Audio** -> **Monitoring Device** -> `rcp_duo_chat_in` |

**Note:** "System" is `rcp_duo_system_in`, set as the PipeWire default sink by
`default-devices.conf`. Most apps route there with no configuration. Only apps that
need to appear on the Chat channel of the RODECaster require a manual device selection.

---

## 4. Default Devices

`configs/audio/default-devices.conf.example` sets:

- **Default sink:** `rcp_duo_system_in` — all program audio routes to the RODECaster
  System channel by default
- **Default source:** RODECaster Duo ALSA input directly (the `alsa_input.usb-...`
  device), identified by serial number

The RODECaster's onboard DSP provides noise gate, compressor, and APHEX aural exciter
processing on the mic signal. No software noise suppression is needed — do not add
RNNoise or similar filters.

The script substitutes `CHANGEME_RODECASTER_SERIAL` in the config with the serial you
provided at the top of `scripts/05-audio-setup.sh`.

---

## 5. Radeon iGPU HDMI Audio

`configs/audio/51-disable-radeon-hdmi-audio.conf.example` is a WirePlumber rule that
disables the Radeon integrated GPU's HDMI audio device. This prevents the iGPU audio
from consuming PipeWire ports and causing startup port exhaustion on systems with many
audio devices.

**This config requires hardware-specific adjustment.** The `device.name` pattern in the
example file is a placeholder and must be updated to match your hardware before deploying.

Find your Radeon iGPU HDMI audio device name:

```bash
wpctl status | grep -i hdmi
```

Update the `device.name` pattern in the config to match. For example, a Radeon iGPU at
PCI address `0000:09:00.1` would use:

```
device.name = "~alsa_card.pci-0000_09_00.1.*"
```

**Note:** This config disables the Radeon iGPU audio only. The GB202 (NVIDIA) HDMI
audio for the LG 5K2K monitor is intentionally left active — it may be needed for
monitor speakers.

---

## 6. Firefox Audio

`configs/audio/firefox-audio.conf.example` sets two environment variables via
`~/.config/environment.d/`:

```ini
FIREFOX_PIPEWIRE=1
MOZ_ENABLE_WAYLAND=1
```

- `FIREFOX_PIPEWIRE=1` — instructs Firefox to use PipeWire directly rather than the
  PulseAudio compatibility layer. Eliminates audio dropouts and improves latency.
- `MOZ_ENABLE_WAYLAND=1` — enables Firefox's native Wayland backend under KDE Plasma.

**Changes take effect on next login** (loaded by systemd user environment via
`environment.d`). No Firefox restart is needed; log out and back in once.

---

## 7. Plex Media Server and Avahi

### Plex Media Server

`configs/audio/plexmediaserver-override.conf.example` is a systemd drop-in that adds
a mount dependency to the Plex Media Server service:

```ini
[Unit]
After=mnt-CHANGEME_MEDIA_MOUNT.mount
Requires=mnt-CHANGEME_MEDIA_MOUNT.mount
```

Without this override, Plex starts at boot before `/mnt/media` is mounted, fails to
find its library, and requires a manual service restart. The override ensures Plex
waits for the media drive.

The script deploys this to `/etc/systemd/system/plexmediaserver.service.d/override.conf`
and runs `sudo systemctl daemon-reload`.

### Avahi

Avahi (`avahi-daemon`) provides network service discovery via mDNS/DNS-SD. It is
required for WiVRn VR headset pairing over the local network. The script enables and
starts the service:

```bash
sudo systemctl enable --now avahi-daemon
```

Both Plex and Avahi are handled automatically by `scripts/05-audio-setup.sh`.

---

## 8. Troubleshooting

### Virtual sinks not showing in `wpctl status`

- Verify `rodecaster-duo-pipewire` is installed: `yay -Q rodecaster-duo-pipewire`
- Ensure the RODECaster Duo is connected via USB
- Confirm Pro Audio mode is activated on the device (check device display)
- Restart PipeWire: `systemctl --user restart pipewire pipewire-pulse wireplumber`

### Firefox audio dropouts or crackling

- Check `99-quantum.conf` is deployed: `cat ~/.config/pipewire/pipewire.conf.d/99-quantum.conf`
- Restart PipeWire after deploying: `systemctl --user restart pipewire pipewire-pulse wireplumber`

### No audio output after setup

```bash
systemctl --user restart pipewire pipewire-pulse wireplumber
```

Check that the default sink is set correctly:

```bash
wpctl status | grep -A5 "Audio"
```

### Wrong default audio device

- Verify `default-devices.conf` is in `~/.config/pipewire/pipewire.conf.d/`
- Confirm the serial number in the config matches your device: `pactl list sources short | grep RODECaster`
- Restart WirePlumber: `systemctl --user restart wireplumber`

### Realtime priority not applied

The realtime group takes effect only after a fresh login. Log out and back in after
running the script. Verify group membership:

```bash
groups | grep realtime
```

### Plex not finding media library

Check the service status and mount dependency:

```bash
systemctl status plexmediaserver
systemctl status mnt-CHANGEME_MEDIA_MOUNT.mount
```

If `/mnt/media` is not mounted, mount it first (see `docs/01-storage.md`), then
restart Plex: `sudo systemctl restart plexmediaserver`
