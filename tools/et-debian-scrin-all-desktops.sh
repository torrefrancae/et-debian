#!/usr/bin/env bash
# Keep scrin.io visible on every workspace — sticky / follow-desktop only.
# Never raise, activate, or set always-on-top (that steals focus while you work).
set -euo pipefail

MATCH="${ET_SCRIN_WM_CLASS:-scrin.io}"
TRIES="${ET_SCRIN_STICKY_TRIES:-60}"
SLEEP_SECS="${ET_SCRIN_STICKY_SLEEP:-2}"
WATCH_SECS="${ET_SCRIN_STICKY_WATCH_SECS:-5}"

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

current_desktop() {
  if command -v xdotool >/dev/null 2>&1; then
    xdotool get_desktop 2>/dev/null && return 0
  fi
  wmctrl -d 2>/dev/null | awk '/\*/{print $1; exit}'
}

is_sticky() {
  local wid="$1" state desk
  state="$(xprop -id "$wid" _NET_WM_STATE 2>/dev/null || true)"
  desk="$(xprop -id "$wid" _NET_WM_DESKTOP 2>/dev/null || true)"
  [[ "${state}" == *_NET_WM_STATE_STICKY* ]] || [[ "${desk}" == *4294967295* ]]
}

has_above() {
  local wid="$1" state
  state="$(xprop -id "$wid" _NET_WM_STATE 2>/dev/null || true)"
  [[ "${state}" == *_NET_WM_STATE_ABOVE* ]]
}

make_sticky() {
  local wid="$1"
  # Do NOT activate/raise — that puts scrin on top of the app you're using.
  # Never mix remove+add in one wmctrl -b list (that strips sticky).
  wmctrl -i -r "$wid" -b remove,above 2>/dev/null || true
  wmctrl -i -r "$wid" -b add,sticky 2>/dev/null || true
  wmctrl -i -r "$wid" -t -1 2>/dev/null || true
  command -v xdotool >/dev/null 2>&1 && xdotool set_desktop_for_window "$wid" -1 2>/dev/null || true
  wmctrl -i -r "$wid" -b add,sticky 2>/dev/null || true
  wmctrl -i -r "$wid" -b remove,above 2>/dev/null || true
}

follow_desktop() {
  local wid="$1" desk="$2"
  [[ -n "${desk}" ]] || return 0
  # Move without activating.
  wmctrl -i -r "$wid" -t "${desk}" 2>/dev/null || true
  command -v xdotool >/dev/null 2>&1 && xdotool set_desktop_for_window "$wid" "${desk}" 2>/dev/null || true
  wmctrl -i -r "$wid" -b remove,above 2>/dev/null || true
}

wid=""
for ((i = 1; i <= TRIES; i++)); do
  wid="$(find_wid || true)"
  if [[ -n "${wid}" ]]; then
    make_sticky "${wid}"
    if is_sticky "${wid}"; then
      log "sticky on all desktops: ${wid}"
    else
      desk="$(current_desktop || true)"
      follow_desktop "${wid}" "${desk}"
      log "sticky unsupported — follow-desktop mode on ${wid} (desk=${desk:-?})"
    fi
    break
  fi
  sleep "${SLEEP_SECS}"
done

last_desk=""
while true; do
  wid="$(find_wid || true)"
  desk="$(current_desktop || true)"
  if [[ -n "${wid}" ]]; then
    if has_above "${wid}"; then
      wmctrl -i -r "$wid" -b remove,above 2>/dev/null || true
      log "cleared always-on-top: ${wid}"
    fi
    if is_sticky "${wid}"; then
      :
    else
      make_sticky "${wid}"
      if ! is_sticky "${wid}"; then
        if [[ -n "${desk}" && "${desk}" != "${last_desk}" ]]; then
          follow_desktop "${wid}" "${desk}"
          log "follow desktop ${desk}: ${wid}"
        fi
      else
        log "sticky restored: ${wid}"
      fi
    fi
  fi
  last_desk="${desk}"
  sleep "${WATCH_SECS}"
done
