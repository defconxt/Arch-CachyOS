# VPN Namespace Isolation

This guide covers setup and daily use of the ProtonVPN WireGuard namespace on
CachyOS with KDE Plasma. Brave and qBittorrent route all traffic through a
WireGuard tunnel inside a dedicated network namespace (`vpn`). All other
traffic — Steam, Discord, games — uses the normal network connection and is
completely unaffected.

`scripts/06-vpn-setup.sh` automates the full provisioning. This document is
the usage and verification reference for after setup is complete.

---

## 1. Prerequisites

The following packages must be installed before running the setup script.

### pacman Packages

| Package | Purpose |
|---------|---------|
| `wireguard-tools` | WireGuard kernel interface management (`wg`, `wg-quick`) |
| `qbittorrent` | BitTorrent client routed through VPN namespace |
| `libnatpmp` | `natpmpc` binary for NAT-PMP port forward renewal |
| `ufw` | Firewall for veth forwarding rules |

### AUR Packages

| Package | Purpose |
|---------|---------|
| `brave-bin` | Brave browser routed through VPN namespace |

Install:

```bash
sudo pacman -S wireguard-tools qbittorrent libnatpmp ufw
yay -S brave-bin
```

**Note:** These should already be installed if you ran `scripts/06-vpn-setup.sh`.
See the script header for the full prerequisites checklist.

---

## 2. Configuration

### 2.1 WireGuard Config File

Copy the example config and fill in your ProtonVPN WireGuard values:

```bash
cp configs/vpn/proton-vpn.conf.example configs/vpn/proton-vpn.conf
```

Edit `configs/vpn/proton-vpn.conf` and replace every `CHANGEME_` placeholder:

| Placeholder | Where to find it |
|-------------|-----------------|
| `CHANGEME_WG_PRIVATE_KEY` | ProtonVPN dashboard: Downloads -> WireGuard config |
| `CHANGEME_WG_ADDRESS` | Same WireGuard config download (Interface -> Address) |
| `CHANGEME_WG_DNS` | Same WireGuard config download (Interface -> DNS) |
| `CHANGEME_WG_PUBKEY` | Same WireGuard config download (Peer -> PublicKey) |
| `CHANGEME_WG_ENDPOINT` | Same WireGuard config download (Peer -> Endpoint) |

Download your WireGuard config from:
`account.protonvpn.com` -> Downloads -> WireGuard

### 2.2 Setup Script Variables

Before running `scripts/06-vpn-setup.sh`, set the `CHANGEME_` variables at the
top of the script:

| Variable | Description |
|----------|-------------|
| `CHANGEME_USERNAME` | Your Linux username (used for sudoers rule and user service) |
| `CHANGEME_WG_ENDPOINT` | ProtonVPN WireGuard endpoint (`hostname:port`) |
| `CHANGEME_WG_ENDPOINT_IP` | Resolved IP of the endpoint (for routing) |
| `CHANGEME_WG_PUBKEY` | ProtonVPN peer public key |
| `CHANGEME_QBIT_USER` | qBittorrent Web UI username |
| `CHANGEME_QBIT_PASS` | qBittorrent Web UI password |

Find all CHANGEME_ values at once:

```bash
grep -r 'CHANGEME_' .
```

### 2.3 Run Setup

```bash
bash scripts/06-vpn-setup.sh
```

The script is idempotent — safe to re-run. It does not require root; it uses
`sudo` internally where needed.

---

## 3. Manual Usage Commands

The `vpn-namespace.sh` script (deployed to `~/scripts/vpn-namespace.sh` by the
setup script) manages the namespace and launches apps.

| Command | Requires sudo | Description |
|---------|:---:|-------------|
| `sudo vpn-namespace.sh up` | yes | Create network namespace and bring up WireGuard tunnel |
| `sudo vpn-namespace.sh down` | yes | Tear down namespace and all associated state |
| `vpn-namespace.sh status` | no | Show namespace existence, WireGuard handshake, routes, and exit IP |
| `vpn-namespace.sh brave` | no | Launch Brave inside the VPN namespace |
| `vpn-namespace.sh qbit` | no | Launch qBittorrent inside the VPN namespace |

The sudoers rule installed by the setup script (`/etc/sudoers.d/vpn-namespace`)
grants NOPASSWD for `vpn-namespace.sh` so password prompts do not interrupt
desktop entry launches.

---

## 4. Systemd Services

Three services are installed and enabled by `scripts/06-vpn-setup.sh`.

### System Services (auto-start on boot)

| Service | Type | Description |
|---------|------|-------------|
| `vpn-namespace.service` | system | Brings up the WireGuard namespace at boot; tears it down on stop |
| `vpn-portforward.service` | system | NAT-PMP port renewal loop (every 45s); requires `vpn-namespace.service` |

### User Service (auto-start on login)

| Service | Type | Description |
|---------|------|-------------|
| `qbittorrent-vpn.service` | user | Starts qBittorrent inside the namespace 10s after desktop login |

Check service status:

```bash
systemctl status vpn-namespace.service
systemctl status vpn-portforward.service
systemctl --user status qbittorrent-vpn.service
```

---

## 5. Brave Managed Policies

The setup script deploys JSON policies to `/etc/brave/policies/managed/privacy.json`
and `/etc/brave/policies/recommended/defaults.json`. These are enforced by Brave
and cannot be overridden by the user.

### Managed Policies (enforced)

| Policy | Value | Purpose |
|--------|-------|---------|
| `WebRtcIPHandlingPolicy` | `disable_non_proxied_udp` | Prevents WebRTC from leaking the real IP outside the VPN namespace |
| `MetricsReportingEnabled` | `false` | Disables crash and usage metrics reporting to Google |
| `SafeBrowsingExtendedReportingEnabled` | `false` | Disables sending URLs to Safe Browsing for extended analysis |
| `SearchSuggestEnabled` | `false` | Disables sending keystrokes to search provider as you type |
| `DnsOverHttpsMode` | `secure` | Enforces DoH; no plaintext DNS fallback |
| `AutofillAddressEnabled` | `false` | Disables address autofill |
| `AutofillCreditCardEnabled` | `false` | Disables payment autofill |
| `PasswordManagerEnabled` | `false` | Disables built-in password manager |
| `DefaultNotificationsSetting` | `2` | Block all notification permission requests |
| `DefaultGeolocationSetting` | `2` | Block all geolocation permission requests |
| `BackgroundModeEnabled` | `false` | Prevents Brave from running in the background |

### Recommended Policies (user can override)

| Policy | Value | Purpose |
|--------|-------|---------|
| `HttpsOnlyMode` | `force_enabled` | HTTPS-only browsing with upgrade fallback |
| `BlockThirdPartyCookies` | `true` | Block third-party cookies |
| `DefaultPopupsSetting` | `2` | Block pop-ups by default |
| `PromptForDownloadLocation` | `true` | Ask where to save each download |

**Verify policies are active:** Open `brave://policy` in Brave after launch.
All entries should show status "Active".

**Manual steps after setup (brave://settings):**

- Shields: Trackers & Ads -> Aggressive
- Privacy: Disable P3A, usage ping, Google push messaging
- Rewards: Disable entirely
- Web3: Default wallets -> Extensions (no fallback)

---

## 6. Desktop Entry Overrides

The setup script patches the Brave and qBittorrent `.desktop` files in
`~/.local/share/applications/` so that launching either app from the KDE
application menu automatically routes them through the VPN namespace.

- `~/.local/share/applications/brave-browser.desktop` — `Exec=` line replaced with
  `sudo ~/scripts/vpn-namespace.sh brave %U`
- `~/.local/share/applications/org.qbittorrent.qBittorrent.desktop` — `Exec=` line
  replaced with `sudo ~/scripts/vpn-namespace.sh qbit`

Verify the overrides are in place:

```bash
grep "Exec=" ~/.local/share/applications/brave-browser.desktop
grep "Exec=" ~/.local/share/applications/org.qbittorrent.qBittorrent.desktop
```

Both should reference `vpn-namespace.sh`.

---

## 7. NAT-PMP Port Forwarding

The `vpn-portforward.service` runs `~/scripts/vpn-portforward.sh` in a loop.

**What it does:**

1. Uses `natpmpc` inside the VPN namespace to request a port mapping from the
   ProtonVPN NAT-PMP gateway (`10.2.0.1`)
2. Renews the UDP and TCP lease every 45 seconds (ProtonVPN leases expire after 60s)
3. Detects port changes and updates qBittorrent's listening port via the
   qBittorrent Web UI API (`http://10.200.200.2:8080/api/v2/app/setPreferences`)

**Important:** Port forwarding only works on ProtonVPN P2P servers. Standard servers
do not support NAT-PMP. Select a server marked "P2P" on the ProtonVPN dashboard.

**Troubleshooting port forwarding:**

- `systemctl status vpn-portforward.service` — check for errors
- If `natpmpc` returns nothing: confirm you are on a P2P server
- If qBittorrent port is not updating: confirm Web UI is enabled and the
  `CHANGEME_QBIT_USER` / `CHANGEME_QBIT_PASS` values in the script match your
  qBittorrent settings

---

## 8. Verification Commands

Run these after `vpn-namespace.sh up` to confirm the namespace is working correctly.

```bash
# Confirm the namespace exists
ip netns list | grep vpn

# Confirm WireGuard handshake (look for "latest handshake" timestamp)
sudo ip netns exec vpn wg show wg0

# Confirm exit IP is a ProtonVPN IP (not your real IP)
sudo ip netns exec vpn curl -s https://ipinfo.io/ip

# Confirm qBittorrent is running inside the namespace
pgrep -a qbittorrent
# Take the PID from the output, then:
sudo nsenter -t <PID> -n ip route
# Expected output: default dev wg0

# Systemd service status
systemctl status vpn-namespace.service
systemctl status vpn-portforward.service
systemctl --user status qbittorrent-vpn.service
```

---

## 9. ProtonVPN Config Rotation

When rotating to a different ProtonVPN server or after key expiry:

1. **Generate a new WireGuard config** from the ProtonVPN dashboard:
   `account.protonvpn.com` -> Downloads -> WireGuard -> select new server

2. **Update `configs/vpn/proton-vpn.conf`** with the new keys and endpoint:
   - `PrivateKey`
   - `Address`
   - `DNS`
   - `PublicKey` (Peer section)
   - `Endpoint` (Peer section)

3. **Restart the namespace** to apply the new config:

   ```bash
   sudo vpn-namespace.sh down && sudo vpn-namespace.sh up
   ```

4. **Verify** the exit IP changed to the new server:

   ```bash
   sudo ip netns exec vpn curl -s https://ipinfo.io/ip
   ```

If switching to a P2P server from a non-P2P server (or vice versa), also restart
`vpn-portforward.service`:

```bash
sudo systemctl restart vpn-portforward.service
```

---

## 10. KDE Session Note

In KDE System Settings: **Session** -> **Desktop Session** -> set
**On login, launch apps that were open** to **Start with empty session**.

Without this, KDE restores the previous session on login. Apps that were open
inside the VPN namespace will attempt to relaunch before `vpn-namespace.service`
has started, causing them to open outside the namespace or fail to launch. The
`qbittorrent-vpn.service` user service handles qBittorrent autostart correctly
once the namespace is up.

---

## 11. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| qBittorrent fails at login / cannot connect | VPN namespace not ready yet | `systemctl --user restart qbittorrent-vpn` after namespace is up |
| Port forwarding not working | Not on a ProtonVPN P2P server | Switch to a P2P-enabled server in the ProtonVPN dashboard |
| DNS leak detected | `/etc/netns/vpn/resolv.conf` missing or wrong | Check: `cat /etc/netns/vpn/resolv.conf` — should show `nameserver 10.2.0.1` |
| Brave not routing through VPN | Desktop entry `Exec=` not overridden | Verify: `grep Exec ~/.local/share/applications/brave-browser.desktop` should reference `vpn-namespace.sh` |
| WireGuard handshake fails | Wrong endpoint IP or public key | Re-check `CHANGEME_WG_ENDPOINT_IP` and `CHANGEME_WG_PUBKEY` in `vpn-namespace.sh` |
| Namespace already exists error | Previous session not cleaned up | `sudo vpn-namespace.sh down` then `sudo vpn-namespace.sh up` |
| Brave KWallet hang | `~/.config/brave-flags.conf` missing | Verify: `cat ~/.config/brave-flags.conf` — should contain `--password-store=basic` |
