#!/usr/bin/env bash
# Keep scrin.io on every GNOME/X11 workspace ("Always on Visible Workspace").
# Sticky only — never always-on-top. Re-asserts forever (Electron/mutter drop it).
set -euo pipefail

MATCH="${ET_SCRIN_WM_CLASS:-scrin.io}"
TRIES="${ET_SCRIN_STICKY_TRIES:-60}"
SLEEP_SECS="${ET_SCRIN_STICKY_SLEEP:-2}"
WATCH_SECS="${ET_SCRIN_STICKY_WATCH_SECS:-10}"

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
  local wid="$1" state desk
  state="$(xprop -id "$wid" _NET_WM_STATE 2>/dev/null || true)"
  desk="$(xprop -id "$wid" _NET_WM_DESKTOP 2>/dev/null || true)"
  [[ "${state}" == *_NET_WM_STATE_STICKY* ]] || [[ "${desk}" == *4294967295* ]]
}

make_sticky() {
  local wid="$1"
  # mutter often ignores sticky unless the window has been activated.
  # Never mix remove+add in one wmctrl -b list (that strips sticky).
  wmctrl -i -a "$wid" 2>/dev/null || true
  command -v xdotool >/dev/null 2>&1 && xdotool windowactivate --sync "$wid" 2>/dev/null || true
  wmctrl -i -r "$wid" -b remove,above 2>/dev/null || true
  wmctrl -i -r "$wid" -b add,sticky 2>/dev/null || true
  wmctrl -i -r "$wid" -t -1 2>/dev/null || true
  command -v xdotool >/dev/null 2>&1 && xdotool set_desktop_for_window "$wid" -1 2>/dev/null || true
  xprop -id "$wid" -f _NET_WM_DESKTOP 32c -set _NET_WM_DESKTOP 0xFFFFFFFF 2>/dev/null || true
  wmctrl -i -r "$wid" -b add,sticky 2>/dev/null || true
  wmctrl -i -r "$wid" -t -1 2>/dev/null || true
  wmctrl -i -r "$wid" -b remove,above 2>/dev/null || true
}

wid=""
for ((i = 1; i <= TRIES; i++)); do
  wid="$(find_wid || true)"
  if [[ -n "${wid}" ]]; then
    make_sticky "${wid}"
    if is_sticky "${wid}"; then
      log "sticky on all desktops: ${wid}"
      break
    fi
    log "sticky not held yet for ${wid} — retry"
  fi
  sleep "${SLEEP_SECS}"
done

# Stay alive: mutter/Electron drop sticky; re-assert without always-on-top.
while true; do
  wid="$(find_wid || true)"
  if [[ -n "${wid}" ]]; then
    if ! is_sticky "${wid}"; then
      make_sticky "${wid}"
      if is_sticky "${wid}"; then
        log "re-assert sticky: ${wid}"
      fi
    else
      wmctrl -i -r "$wid" -b remove,above 2>/dev/null || true
    fi
  fi
  sleep "${WATCH_SECS}"
done
