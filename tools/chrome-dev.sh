#!/usr/bin/env bash
# Installed as /usr/local/bin/chrome-dev by scripts/50-tools.sh
# On et-debian / et-debianvm: quit this user's Chrome, then relaunch with DevTools open.
# Same flow as Mac chrome-dev. Does not pin a device viewport.
# Only this user's chrome processes are signaled, so a kiosk user stays up.
#
# Usage:
#   chrome-dev
#   chrome-dev https://example.test
#   CHROME_DEV_DISPLAY=:10 chrome-dev
#
# With no URL args, opens $CHROME_DEV_ROOT (default: ~/proj/dev) as a file URL.
set -euo pipefail

log() { printf '[chrome-dev] %s\n' "$*" >&2; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  printf '%s\n' \
    "Usage: chrome-dev [url...]" \
    "Quit this user's Chrome and relaunch it with DevTools open." \
    "Default URL/path: \${CHROME_DEV_ROOT:-~/proj/dev}"
  exit 0
fi

: "${CHROME_DEV_BIN:=}"
: "${CHROME_DEV_DISPLAY:=}"
: "${CHROME_DEV_ROOT:=$HOME/proj/dev}"

_expand_home() {
  local p="$1"
  case "$p" in
    "~/"*) printf '%s\n' "${HOME}/${p#~/}" ;;
    "~") printf '%s\n' "$HOME" ;;
    *) printf '%s\n' "$p" ;;
  esac
}

_default_url() {
  local root
  root="$(_expand_home "$CHROME_DEV_ROOT")"
  if [[ -d "$root" ]]; then
    printf 'file://%s/\n' "$root"
  elif [[ -e "$root" ]]; then
    printf 'file://%s\n' "$root"
  else
    printf 'file://%s/\n' "$(_expand_home "$HOME/proj/dev")"
  fi
}

_find_chrome() {
  if [[ -n "$CHROME_DEV_BIN" && -x "$CHROME_DEV_BIN" ]]; then
    printf '%s\n' "$CHROME_DEV_BIN"
    return 0
  fi
  local c
  for c in \
    /usr/bin/google-chrome-stable \
    /usr/bin/google-chrome \
    /opt/google/chrome/google-chrome \
    /usr/bin/chromium-browser \
    /usr/bin/chromium
  do
    if [[ -x "$c" ]]; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}

_chrome_running() {
  pgrep -u "$(id -u)" -x chrome >/dev/null 2>&1
}

_chrome_dev_quit() {
  if ! _chrome_running; then
    return 0
  fi
  log "quitting Chrome"
  killall -u "$(id -un)" -TERM chrome >/dev/null 2>&1 || true
  local i=0
  while _chrome_running && (( i < 40 )); do
    sleep 0.25
    (( i++ )) || true
  done
  if _chrome_running; then
    log "force-killing Chrome"
    killall -u "$(id -un)" -KILL chrome >/dev/null 2>&1 || true
    sleep 0.5
  fi
  sleep 0.5
}

_pick_display() {
  if [[ -n "$CHROME_DEV_DISPLAY" ]]; then
    printf '%s\n' "$CHROME_DEV_DISPLAY"
    return 0
  fi
  if [[ -n "${DISPLAY:-}" ]]; then
    printf '%s\n' "$DISPLAY"
    return 0
  fi
  local line sid name type remote display seat fallback=""
  while IFS= read -r line; do
    sid="${line%% *}"
    [[ -n "$sid" ]] || continue
    name="$(loginctl show-session "$sid" -p Name --value 2>/dev/null || true)"
    [[ "$name" == "$(id -un)" ]] || continue
    type="$(loginctl show-session "$sid" -p Type --value 2>/dev/null || true)"
    remote="$(loginctl show-session "$sid" -p Remote --value 2>/dev/null || true)"
    display="$(loginctl show-session "$sid" -p Display --value 2>/dev/null || true)"
    seat="$(loginctl show-session "$sid" -p Seat --value 2>/dev/null || true)"
    [[ "$type" == "x11" && -n "$display" ]] || continue
    if [[ "$remote" == "no" || "$seat" == "seat0" ]]; then
      printf '%s\n' "$display"
      return 0
    fi
    if [[ -z "$fallback" ]]; then
      fallback="$display"
    fi
  done < <(loginctl list-sessions --no-legend 2>/dev/null || true)
  if [[ -n "$fallback" ]]; then
    printf '%s\n' "$fallback"
    return 0
  fi
  return 1
}

chrome="$( _find_chrome )" || {
  log "Google Chrome not found"
  exit 1
}

display="$( _pick_display )" || {
  log "no X11 display for $(id -un); set DISPLAY or CHROME_DEV_DISPLAY"
  exit 1
}

export DISPLAY="$display"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -S "$XDG_RUNTIME_DIR/bus" ]]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
fi

log "chrome=$chrome"
log "DISPLAY=$DISPLAY"

_chrome_dev_quit

launch_args=("$@")
if [[ ${#launch_args[@]} -eq 0 ]]; then
  launch_args=("$( _default_url )")
  log "default root: ${launch_args[0]}"
fi

log "launching with --auto-open-devtools-for-tabs"
if command -v setsid >/dev/null 2>&1; then
  setsid "$chrome" --auto-open-devtools-for-tabs "${launch_args[@]}" </dev/null >/dev/null 2>&1 &
else
  nohup "$chrome" --auto-open-devtools-for-tabs "${launch_args[@]}" </dev/null >/dev/null 2>&1 &
  disown || true
fi
sleep 0.4
if _chrome_running; then
  log "Chrome started on $DISPLAY"
else
  log "Chrome may still be starting on $DISPLAY"
fi

