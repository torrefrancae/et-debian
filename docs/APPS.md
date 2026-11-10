# Codified lab apps (native — no Docker)

Installed by `scripts/40-apps.sh` + `scripts/30-desktop.sh` on bootstrap.

| App | Role | How |
|-----|------|-----|
| **xrdp + xorgxrdp** | Remote desktop (:3389) | apt; GDM `WaylandEnable=false` |
| **Google Chrome** | Browser | official `.deb` |
| **Cursor** | Editor | Cursor aptrepo / golden `.deb` |
| **Screenshot Monitor** 1.3.1 | Time/screenshot capture | S3 `.deb` + `mono-complete` + Bookworm `gtk-sharp2` stack; autostart for **et-dev** |
| **AnyDesk** | Remote assistance | pinned amd64 `.deb` (override `ANYDESK_AMD64_URL`) |
| **Remmina** (+ RDP/VNC plugins) | Client remotes | apt |
| **TigerVNC viewer** | VNC client | apt |
| **modifier-hud** | Ctrl/Shift/Cmd OSD | `scripts/50-tools.sh` |
| **Sleep / wake** | Suspend **06:00**, RTC wake **15:00** (local) | `scripts/60-power.sh` → `et-debian-sleep.timer` + `rtcwake` |

Hold overnight awake: `sudo touch /etc/et-debian-nosleep` (remove the file to resume the schedule).  
BIOS may need **Wake on RTC / Alarm** enabled for the afternoon resume.

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
