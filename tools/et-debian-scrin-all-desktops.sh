#!/usr/bin/env bash
# Keep scrin.io visible on every GNOME/X11 workspace ("Always on Visible Workspace").
# Waits for the window, then sets sticky + desktop 0xFFFFFFFF. No Docker.
set -euo pipefail

MATCH="${ET_SCRIN_WM_CLASS:-scrin.io}"
TRIES="${ET_SCRIN_STICKY_TRIES:-60}"
SLEEP_SECS="${ET_SCRIN_STICKY_SLEEP:-2}"

log() { printf '[et-debian-scrin] %s\n' "$*"; }

if [[ -z "${DISPLAY:-}" ]]; then
  log "no DISPLAY — skip"
  exit 0
fi
command -v wmctrl >/dev/null 2>&1 || { log "wmctrl missing"; exit 0; }
command -v xprop >/dev/null 2>&1 || { log "xprop missing"; exit 0; }

find_wid() {
  wmctrl -lx 2>/dev/null | awk -v m="$MATCH" 'BEGIN{IGNORECASE=1} index($3,m)||index($0,m){print $1; exit}'
}

make_sticky() {
  local wid="$1"
  # Sticky = all workspaces. Never keep "above" (always-on-top) — scrin.io must stay
  # reachable on every desktop without covering other apps.
  wmctrl -i -r "$wid" -b remove,above 2>/dev/null || true
  wmctrl -i -r "$wid" -b add,sticky 2>/dev/null || true
  xprop -id "$wid" -f _NET_WM_DESKTOP 32c -set _NET_WM_DESKTOP 0xFFFFFFFF 2>/dev/null || true
  wmctrl -i -r "$wid" -t -1 2>/dev/null || true
  wmctrl -i -r "$wid" -b remove,above,add,sticky 2>/dev/null || true
}

wid=""
for ((i = 1; i <= TRIES; i++)); do
  wid="$(find_wid || true)"
  if [[ -n "${wid}" ]]; then
    make_sticky "${wid}"
    log "sticky on all desktops: ${wid}"
    break
  fi
  sleep "${SLEEP_SECS}"
done

if [[ -z "${wid}" ]]; then
  log "scrin.io window not found after ${TRIES} tries — exit"
  exit 0
fi

# Re-assert a few times (Electron can recreate/reparent the window after login UI)
for _ in 1 2 3 4 5; do
  sleep 5
  wid="$(find_wid || true)"
  [[ -n "${wid}" ]] || continue
  make_sticky "${wid}"
done

exit 0
