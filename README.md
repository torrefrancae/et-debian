# et-debian

Public, **Docker-free** bootstrap for a Debian 13 (trixie) lab PC named `et-debian`.

Goal: wipe / reinstall Debian desktop, then re-apply this repo and be productive in minutes — without paying Docker’s RAM/CPU tax. Workloads run **natively** (apt packages, systemd, xrdp, linuxnative-style app stacks).

## What this is

| In the repo (public) | Kept private (not here) |
|----------------------|-------------------------|
| Host bootstrap scripts | Passwords, VPN profiles, SSH private keys |
| Desktop/RDP/base package lists | Agent / Seatrix rule packs |
| Lab apps: RDP, Chrome, Cursor, Screenshot Monitor, AnyDesk, Remmina | Camera / VPN / AnyDesk unattended passwords |
| Small tools (modifier-hud, helpers) | Machine-local `~/proj` product trees |

## Requirements

1. Fresh **Debian 13** GNOME desktop install, hostname preferably `et-debian`.
2. User `et` exists (installer default). Root password known (same as `et` is fine).
3. Network access for `apt` and optional app downloads.

## Quick start (on the new PC)

```bash
sudo apt-get update
sudo apt-get install -y git curl ca-certificates
git clone https://github.com/torrefrancae/et-debian.git ~/et-debian
cd ~/et-debian
# as et — script will elevate via su/root when needed
./scripts/bootstrap.sh
```

Or from another machine with SSH:

```bash
ssh et@et-debian.local 'bash -s' < scripts/bootstrap.sh
```

## Design rules

- **No Docker / Podman / compose** in the default path.
- Scripts are idempotent where practical (safe to re-run).
- Secrets live in `private/` (gitignored) or the operator’s head — never in git.
- Product code (Seatrix, etc.) stays in `~/proj/dev/...` and is **not** published by this repo.

## Layout

```
scripts/bootstrap.sh     # entrypoint
scripts/10-base.sh       # apt base + timezone + avahi/ssh
scripts/20-users.sh      # etshare, et-dev, et-startup (optional)
scripts/30-desktop.sh    # X11 preference, xrdp (:3389)
scripts/40-apps.sh       # Chrome, Cursor, Screenshot Monitor, AnyDesk, Remmina
scripts/50-tools.sh      # modifier-hud and small helpers
tools/                   # source for helpers installed under /usr/local
docs/APPS.md             # codified app inventory
docs/SECURITY.md         # what must never be committed
```

See [docs/APPS.md](docs/APPS.md) for the full native app list.

## Mac / operator notes

Host lookup on the controlling Mac belongs in `~/proj/config/pcNN` (local, not this repo).  
RDP launchers and SSH mux wrappers stay on the Mac under `~/proj/config` / `~/proj/dev`.
