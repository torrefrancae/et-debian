#!/usr/bin/env bash
# Super+Left/Right → switch workspace (not tile/snap window).
# Safe to re-run. No Docker.
set -euo pipefail

log() { logger -t et-debian-keys "$*"; printf '[et-debian-keys] %s\n' "$*"; }

apply_for_user() {
  local u="$1"
  local uid bus
  uid="$(id -u "${u}")"
  bus="/run/user/${uid}/bus"

  run_gs() {
    if [[ -S "${bus}" ]]; then
      sudo -u "${u}" DBUS_SESSION_BUS_ADDRESS="unix:path=${bus}" gsettings "$@"
    else
      sudo -u "${u}" dbus-run-session -- gsettings "$@" 2>/dev/null
    fi
  }

  # Free Super+Left/Right from mutter tiling
  run_gs set org.gnome.mutter.keybindings toggle-tiled-left "[]" || true
  run_gs set org.gnome.mutter.keybindings toggle-tiled-right "[]" || true
  run_gs set org.gnome.mutter edge-tiling false || true

  # Bind them to workspace switch
  run_gs set org.gnome.desktop.wm.keybindings switch-to-workspace-left "['<Super>Left']" || true
  run_gs set org.gnome.desktop.wm.keybindings switch-to-workspace-right "['<Super>Right']" || true

  # Keep a fixed strip of workspaces so Left/Right always have somewhere to go
  run_gs set org.gnome.mutter dynamic-workspaces false || true
  run_gs set org.gnome.desktop.wm.preferences num-workspaces 4 || true

  log "Super+Left/Right → workspace switch for ${u}"
}

# System dconf so new sessions inherit
if [[ "${EUID}" -eq 0 ]]; then
  install -d /etc/dconf/db/local.d /etc/dconf/profile
  if [[ ! -f /etc/dconf/profile/user ]]; then
    cat >/etc/dconf/profile/user <<'EOF'
user-db:user
system-db:local
EOF
  fi
  cat >/etc/dconf/db/local.d/00-et-debian-workspaces <<'EOF'
[org/gnome/mutter]
edge-tiling=false
dynamic-workspaces=false

[org/gnome/mutter/keybindings]
toggle-tiled-left=@as []
toggle-tiled-right=@as []

[org/gnome/desktop/wm/keybindings]
switch-to-workspace-left=['<Super>Left']
switch-to-workspace-right=['<Super>Right']

[org/gnome/desktop/wm/preferences]
num-workspaces=4
EOF
  if command -v dconf >/dev/null 2>&1; then
    dconf update || true
  fi
  for u in et; do
    if id "${u}" >/dev/null 2>&1; then
      apply_for_user "${u}"
    fi
  done
else
  # non-root: apply to current user only
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"
  gsettings set org.gnome.mutter.keybindings toggle-tiled-left "[]" || true
  gsettings set org.gnome.mutter.keybindings toggle-tiled-right "[]" || true
  gsettings set org.gnome.mutter edge-tiling false || true
  gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-left "['<Super>Left']" || true
  gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-right "['<Super>Right']" || true
  gsettings set org.gnome.mutter dynamic-workspaces false || true
  gsettings set org.gnome.desktop.wm.preferences num-workspaces 4 || true
  log "Super+Left/Right → workspace switch for $(id -un)"
fi
