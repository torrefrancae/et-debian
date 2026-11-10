# Codified lab apps (native — no Docker)

Installed by `scripts/40-apps.sh` + `scripts/30-desktop.sh` on bootstrap.

| App | Role | How |
|-----|------|-----|
| **xrdp + xorgxrdp** | Remote desktop (:3389) | apt; GDM `WaylandEnable=false` |
| **Google Chrome** | Browser | official `.deb` |
| **Cursor** | Editor | Cursor aptrepo / golden `.deb` |
| **scrin.io** 1.0.7 | Time/screenshot capture (Electron) | modern `scrin.io` `.deb` (amd64); autostart for **et**; sticky on all workspaces via `et-debian-scrin-all-desktops` |
| **AnyDesk** | Remote assistance | pinned amd64 `.deb` (override `ANYDESK_AMD64_URL`) |
| **Remmina** (+ RDP/VNC plugins) | Client remotes | apt |
| **TigerVNC viewer** | VNC client | apt |
| **modifier-hud** | Ctrl/Shift/Cmd OSD | `scripts/50-tools.sh` |
| **Sleep / wake** | Suspend **06:00**, RTC wake **15:00** (local) | `scripts/60-power.sh` → `et-debian-sleep.timer` + `rtcwake` |
| **Idle / display** | No fake black blank; **physical panel real-off** (DRM dpms + backlight); machine stays awake | `et-debian-panel-off` at boot + idle helper; only 06:00 timer suspends |
| **RTC wake enable** | Kernel/ACPI alarm wake from Debian | `et-debian-enable-rtc-wake` (sysfs `wakeup=enabled`, ACPI `RTC*` on, prefer `mem_sleep=deep`) |

Hold overnight awake: `sudo touch /etc/et-debian-nosleep` (remove the file to resume the schedule).

Idle and lid sleep are off; the only intended suspend is the 06:00 timer (wake 15:00). Debian enables RTC wake in-OS when the firmware exposes it.

## Intentionally not in the public bootstrap

- Docker / Podman
- OpenVPN profiles, CCTV RTSP credentials, go2rtc camera YAML
- AnyDesk unattended password
- Seatrix / product trees under `~/proj/dev`

## Overrides

```bash
export SSM_DEB_URL='https://screenshotmonitor-download.s3.amazonaws.com/linux/ScreenshotMonitor.deb'
export ANYDESK_AMD64_URL='https://download.anydesk.com/linux/anydesk_6.4.0-1_amd64.deb'
./scripts/bootstrap.sh
```
