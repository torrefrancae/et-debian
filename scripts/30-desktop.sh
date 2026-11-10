#!/usr/bin/env bash
# GNOME + X11 preference + xrdp (native RDP server). No Docker.
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

# Prefer Xorg for RDP / modifier-hud / Screenshot Monitor (X11 APIs)
log "prefer WaylandEnable=false for gdm3 (RDP-friendly)"
as_root bash -c '
  conf=/etc/gdm3/daemon.conf
  if [[ ! -f "$conf" ]]; then exit 0; fi
  if grep -q "^WaylandEnable=" "$conf"; then
    sed -i "s/^WaylandEnable=.*/WaylandEnable=false/" "$conf"
  else
    if grep -q "^\[daemon\]" "$conf"; then
      sed -i "/^\[daemon\]/a WaylandEnable=false" "$conf"
    else
      printf "\n[daemon]\nWaylandEnable=false\n" >> "$conf"
    fi
  fi
'

# xrdp: listen on all interfaces, port 3389 (do not pin to a Wi-Fi IP)
as_root bash -c '
  conf=/etc/xrdp/xrdp.ini
  if [[ -f "$conf" ]]; then
    sed -i "s/^port=.*/port=3389/" "$conf" || true
    sed -i "s/^address=.*/address=0.0.0.0/" "$conf" || true
  fi
'

# Default session: GNOME on Xorg when startwm is stock
if as_root test -f /etc/xrdp/startwm.sh; then
  as_root bash -c '
    if ! grep -q "gnome-session\|startplasma\|xfce" /etc/xrdp/startwm.sh 2>/dev/null; then
      true
    fi
    # Ensure we do not exec a broken .xsession-errors path; leave distro startwm.
    chmod 755 /etc/xrdp/startwm.sh
  '
fi

as_root systemctl enable --now xrdp || true
as_root systemctl enable --now xrdp-sesman || true

# ssl-cert membership for xrdp cert access
for u in et et-dev et-startup etshare; do
  if id "${u}" >/dev/null 2>&1; then
    as_root usermod -aG ssl-cert "${u}" || true
  fi
done

# Allow RDP through nftables/ufw when those tools manage the firewall
if command -v ufw >/dev/null 2>&1 && as_root ufw status 2>/dev/null | grep -qi active; then
  as_root ufw allow 3389/tcp || true
fi

log "desktop/rdp done — FreeRDP / Microsoft RDP → host:3389 (xrdp + xorgxrdp)"
