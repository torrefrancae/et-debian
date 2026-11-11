#!/usr/bin/env bash
# Keep scrin.io on every GNOME/X11 workspace ("Always on Visible Workspace").
# Sticky only — never always-on-top. Re-asserts forever (Electron can drop sticky).
set -euo pipefail

MATCH="${ET_SCRIN_WM_CLASS:-scrin.io}"
TRIES="${ET_SCRIN_STICKY_TRIES:-60}"
SLEEP_SECS="${ET_SCRIN_STICKY_SLEEP:-2}"
WATCH_SECS="${ET_SCRIN_STICKY_WATCH_SECS:-30}"

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

is_sticky() {
  local wid="$1" desk state
  desk="$(wmctrl -l 2>/dev/null | awk -v id="$wid" '$1==id{print $2; exit}')"
  state="$(xprop -id "$wid" _NET_WM_STATE 2>/dev/null || true)"
  [[ "${desk}" == "-1" ]] || [[ "${state}" == *_NET_WM_STATE_STICKY* ]]
}

make_sticky() {
  local wid="$1"
  # Sticky = all workspaces. Never keep "above" (always-on-top).
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
  log "scrin.io window not found after ${TRIES} tries — keep watching"
fi

# Stay alive: Electron/GNOME often drops sticky after workspace changes or relaunch.
while true; do
  wid="$(find_wid || true)"
  if [[ -n "${wid}" ]]; then
    if ! is_sticky "${wid}"; then
      make_sticky "${wid}"
      log "re-assert sticky: ${wid}"
    else
      # Still strip always-on-top if the app re-adds it.
      wmctrl -i -r "$wid" -b remove,above 2>/dev/null || true
    fi
  fi
  sleep "${WATCH_SECS}"
done
