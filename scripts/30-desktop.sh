#!/usr/bin/env bash
# GNOME + X11 preference + xrdp for remote desktop. No Docker.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

log "desktop / rdp packages"
apt_update
apt_install \
  xorg xrdp xorgxrdp \
  dbus-x11 \
  gnome-session gnome-terminal \
  polkitd pkexec

# Prefer Xorg for RDP/modifier-hud (Wayland is fine locally; xrdp wants X11)
GDM_CONF=/etc/gdm3/daemon.conf
if [[ -f "${GDM_CONF}" ]] || as_root test -f /etc/gdm3/daemon.conf; then
  log "prefer WaylandEnable=false for gdm3 (RDP-friendly)"
  as_root bash -c '
    conf=/etc/gdm3/daemon.conf
    if [[ ! -f "$conf" ]]; then exit 0; fi
    if grep -q "^WaylandEnable=" "$conf"; then
      sed -i "s/^WaylandEnable=.*/WaylandEnable=false/" "$conf"
    else
      printf "\n[daemon]\nWaylandEnable=false\n" >> "$conf"
    fi
  '
fi

as_root systemctl enable --now xrdp || true
as_root systemctl enable --now xrdp-sesman || true

# Allow et in ssl-cert for xrdp cert access when needed
if id et >/dev/null 2>&1; then
  as_root usermod -aG ssl-cert et || true
fi

log "desktop/rdp done — connect with FreeRDP / Microsoft RDP to :3389"
