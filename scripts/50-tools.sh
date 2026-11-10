#!/usr/bin/env bash
# Small native tools from this repo → /usr/local
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TOOLS_SRC="${REPO_ROOT}/tools"
XDG_SRC="${REPO_ROOT}/conf/xdg"

as_root install -d /usr/local/bin /usr/local/share/et-debian

if [[ -f "${TOOLS_SRC}/modifier-hud.py" ]]; then
  log "install modifier-hud"
  as_root install -m 0755 "${TOOLS_SRC}/modifier-hud.py" /usr/local/bin/modifier-hud
  as_root ln -sfn /usr/local/bin/modifier-hud /usr/local/bin/modifier-hud.py
fi

if [[ -f "${TOOLS_SRC}/mouse-circle.sh" ]]; then
  as_root install -m 0755 "${TOOLS_SRC}/mouse-circle.sh" /usr/local/bin/mouse-circle
fi

if [[ -f "${TOOLS_SRC}/chrome-dev.sh" ]]; then
  log "install chrome-dev"
  as_root install -m 0755 "${TOOLS_SRC}/chrome-dev.sh" /usr/local/bin/chrome-dev
fi

if [[ -f "${TOOLS_SRC}/workin.sh" ]]; then
  log "install workin"
  as_root install -m 0755 "${TOOLS_SRC}/workin.sh" /usr/local/bin/workin
fi

if [[ -f "${TOOLS_SRC}/et-debian-workspace-keys.sh" ]]; then
  log "Super+Left/Right → workspace switch (not window snap)"
  as_root install -m 0755 \
    "${TOOLS_SRC}/et-debian-workspace-keys.sh" \
    /usr/local/sbin/et-debian-workspace-keys
  as_root /usr/local/sbin/et-debian-workspace-keys || true
fi

if [[ -f "${TOOLS_SRC}/et-debian-scrin-all-desktops.sh" ]]; then
  log "scrin.io → all virtual desktops helper"
  as_root install -m 0755 \
    "${TOOLS_SRC}/et-debian-scrin-all-desktops.sh" \
    /usr/local/bin/et-debian-scrin-all-desktops
fi

# Autostart for logged-in graphical user (et)
if id et >/dev/null 2>&1; then
  home="$(getent passwd et | cut -d: -f6)"
  as_root install -d -o et -g et "${home}/.config/autostart"
  if [[ -f "${XDG_SRC}/modifier-hud.desktop" ]]; then
    as_root install -m 0644 -o et -g et \
      "${XDG_SRC}/modifier-hud.desktop" \
      "${home}/.config/autostart/modifier-hud.desktop"
  fi
  if [[ -f "${XDG_SRC}/scrin-all-desktops.desktop" ]]; then
    as_root install -m 0644 -o et -g et \
      "${XDG_SRC}/scrin-all-desktops.desktop" \
      "${home}/.config/autostart/scrin-all-desktops.desktop"
  fi
fi

log "tools done"
