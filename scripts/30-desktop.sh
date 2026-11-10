#!/usr/bin/env bash
# GNOME + X11 preference + xrdp (native RDP server). No Docker.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

log "desktop / rdp packages"
apt_update
apt_install \
  xorg xrdp xorgxrdp xserver-xorg-legacy \
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

# Non-console users must be allowed to start Xorg for xrdp sessions
log "Xwrapper allowed_users=anybody (needed by xrdp)"
as_root bash -c '
  conf=/etc/X11/Xwrapper.config
  if [[ -f "$conf" ]]; then
    if grep -q "^allowed_users=" "$conf"; then
      sed -i "s/^allowed_users=.*/allowed_users=anybody/" "$conf"
    else
      echo "allowed_users=anybody" >> "$conf"
    fi
  else
    printf "allowed_users=anybody\nneeds_root_rights=yes\n" > "$conf"
  fi
'

# xrdp.ini: ONLY Globals listens on 3389. Session modules must keep port=-1
# (sesman-assigned). A blanket sed on ^port= breaks login with
# "Error connecting to user session".
log "xrdp.ini Globals listen 0.0.0.0:3389; session ports=-1"
as_root python3 - <<'PY'
from pathlib import Path
path = Path("/etc/xrdp/xrdp.ini")
if not path.exists():
    raise SystemExit(0)
lines = path.read_text().splitlines(True)
out = []
section = None
for line in lines:
    if line.startswith("[") and "]" in line:
        section = line.strip()[1 : line.strip().index("]")]
    if line.startswith("port="):
        if section == "Globals":
            line = "port=3389\n"
        elif section in ("Xorg", "Xvnc", "vnc-any", "neutrinordp-any", "xrdp1"):
            line = "port=-1\n"
    if line.startswith("address=") and section == "Globals":
        line = "address=0.0.0.0\n"
    out.append(line)
path.write_text("".join(out))
PY

# GNOME on Xorg for RDP (do not reuse the console dbus/runtime)
log "install GNOME startwm for xrdp"
as_root tee /etc/xrdp/startwm.sh >/dev/null <<'STARTWM'
#!/bin/sh
# et-debian: GNOME on Xorg for xrdp
if test -r /etc/profile; then . /etc/profile; fi
if test -r ~/.profile; then . ~/.profile; fi
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
export XDG_SESSION_TYPE=x11
export GNOME_SHELL_SESSION_MODE=gnome
export XDG_CURRENT_DESKTOP=GNOME
export XDG_SESSION_DESKTOP=gnome
if test -x /usr/bin/gnome-session; then
  exec /usr/bin/gnome-session
fi
test -x /etc/X11/Xsession && exec /etc/X11/Xsession
exec /bin/sh /etc/X11/Xsession
STARTWM
as_root chmod 755 /etc/xrdp/startwm.sh

if id et >/dev/null 2>&1; then
  home="$(getent passwd et | cut -d: -f6)"
  as_root bash -c "
    install -d -o et -g et '${home}'
    printf '%s\n' 'export XDG_SESSION_TYPE=x11' 'export GNOME_SHELL_SESSION_MODE=gnome' > '${home}/.xsessionrc'
    chown et:et '${home}/.xsessionrc'
  "
  as_root usermod -aG ssl-cert et || true
fi

as_root systemctl enable --now xrdp-sesman || true
as_root systemctl enable --now xrdp || true
as_root systemctl restart xrdp-sesman xrdp || true

# Allow RDP through nftables/ufw when those tools manage the firewall
if command -v ufw >/dev/null 2>&1 && as_root ufw status 2>/dev/null | grep -qi active; then
  as_root ufw allow 3389/tcp || true
fi

log "desktop/rdp done — FreeRDP / Microsoft RDP → host:3389 (xrdp + xorgxrdp)"
