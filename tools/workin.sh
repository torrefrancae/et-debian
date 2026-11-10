#!/usr/bin/env bash
# Installed as /usr/local/bin/workin by scripts/50-tools.sh
# Linux workin for et-debian: open a project path in Cursor (and optional terminal).
# Same CLI shape as the Mac workin where it makes sense on Debian/GNOME.
#
# Usage:
#   workin [--fresh] [--close-only] [--force] [--all] [--browser] [--no-docker]
#          [--app=<tok>[,<tok>...]] <path>
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  workin [--fresh] [--close-only] [--force] [--all] [--browser] [--no-docker]
         [--app=<tok>[,<tok>...]] <path>

Behavior:
  - Default: open Cursor on <path>
  - With --all: also open a terminal in that directory
  - With --fresh: quit selected apps (and stop Docker when available), then reopen
  - With --close-only: only quit selected apps
  - With --browser: open Google Chrome on <path> as a file URL, or https:// if given

Notes:
  - If <path> does not start with ~, ., or /, it is treated as a subpath of
    $WORKIN_ROOT (default: ~/proj/dev)
EOF
}

no_closing="true"
just_close="false"
target=""
open_cursor="true"
open_terminal="false"
app_filter_set="false"
all_apps="false"
force_kill="false"
open_browser="false"
stop_docker="false"
launch_delay="${WORKIN_LAUNCH_DELAY:-1}"

case "${WORKIN_FRESH:-0}" in
  1|true|yes|on)
    no_closing="false"
    stop_docker="true"
    ;;
esac
case "${WORKIN_STOP_DOCKER:-1}" in
  0|false|no|off) stop_docker="false" ;;
esac

enable_app() {
  case "$1" in
    c|cu|cur|cursor) open_cursor="true" ;;
    it|ite|iterm|iterm2|term|terminal|gnome-terminal)
      open_terminal="true"
      ;;
    *)
      echo "workin: unknown --app token: $1 (try c, cursor, term)" >&2
      exit 1
      ;;
  esac
}

apply_app_tokens() {
  local raw="$1" part
  IFS=',' read -r -a parts <<<"$raw"
  for part in "${parts[@]}"; do
    part="$(printf '%s' "$part" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    [[ -n "$part" ]] || continue
    if [[ "$app_filter_set" != "true" ]]; then
      open_cursor="false"
      open_terminal="false"
      app_filter_set="true"
    fi
    enable_app "$part"
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --fresh) no_closing="false"; stop_docker="true"; shift ;;
    --open-only|--no-closing) no_closing="true"; shift ;;
    --close-only|--just-close) just_close="true"; no_closing="false"; shift ;;
    --force) force_kill="true"; shift ;;
    --no-docker) stop_docker="false"; shift ;;
    --all) all_apps="true"; open_cursor="true"; open_terminal="true"; shift ;;
    --browser) open_browser="true"; shift ;;
    --app=*)
      apply_app_tokens "${1#--app=}"
      shift
      ;;
    --app)
      [[ $# -gt 1 ]] || { echo "workin: --app requires a value" >&2; exit 1; }
      apply_app_tokens "$2"
      shift 2
      ;;
    --skip|--skip=*)
      echo "workin: --skip is deprecated; use --app= instead" >&2
      exit 1
      ;;
    --maximize|--fullscreen|--no-maximize|--fulls=*)
      shift
      ;;
    -*)
      echo "workin: unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      if [[ -n "$target" ]]; then
        echo "workin: unexpected extra argument: $1" >&2
        exit 1
      fi
      target="$1"
      shift
      ;;
  esac
done

if [[ -z "$target" ]]; then
  echo "workin: path required" >&2
  usage
  exit 1
fi

if [[ -n "${WORKIN_APP:-}" && "$app_filter_set" != "true" && "$all_apps" != "true" ]]; then
  apply_app_tokens "$WORKIN_APP"
fi

expand_path() {
  local p="$1"
  case "$p" in
    "~/"*) p="${HOME}/${p#~/}" ;;
    "~") p="$HOME" ;;
  esac
  if [[ "$p" != /* && "$p" != ./* && "$p" != ../* && "$p" != . && "$p" != .. ]]; then
    local root="${WORKIN_ROOT:-$HOME/proj/dev}"
    case "$root" in
      "~/"*) root="${HOME}/${root#~/}" ;;
      "~") root="$HOME" ;;
    esac
    p="${root%/}/$p"
  fi
  if command -v realpath >/dev/null 2>&1; then
    realpath -m "$p"
  else
    printf '%s\n' "$p"
  fi
}

target="$(expand_path "$target")"
if [[ ! -e "$target" ]]; then
  echo "workin: path not found: $target" >&2
  exit 1
fi

log() { printf '[workin] %s\n' "$*" >&2; }

_pick_display() {
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

if display="$(_pick_display)"; then
  export DISPLAY="$display"
  export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  if [[ -S "$XDG_RUNTIME_DIR/bus" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
  fi
fi

quit_user_procs() {
  local pat="$1"
  if ! pgrep -u "$(id -u)" -f "$pat" >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$force_kill" == "true" ]]; then
    pkill -u "$(id -u)" -KILL -f "$pat" >/dev/null 2>&1 || true
  else
    pkill -u "$(id -u)" -TERM -f "$pat" >/dev/null 2>&1 || true
    sleep 0.8
    pkill -u "$(id -u)" -KILL -f "$pat" >/dev/null 2>&1 || true
  fi
}

if [[ "$no_closing" != "true" ]]; then
  if [[ "$open_cursor" == "true" ]]; then
    log "closing Cursor"
    quit_user_procs '[/]usr/share/cursor/cursor|/usr/share/cursor/bin/cursor|cursor --'
  fi
  if [[ "$open_terminal" == "true" ]]; then
    log "closing gnome-terminal"
    quit_user_procs 'gnome-terminal|gnome-terminal-server'
  fi
  if [[ "$stop_docker" == "true" ]] && command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
      mapfile -t _cids < <(docker ps -q 2>/dev/null || true)
      if [[ ${#_cids[@]} -gt 0 ]]; then
        log "stopping Docker containers"
        docker stop "${_cids[@]}" >/dev/null 2>&1 || true
      fi
    fi
  fi
fi

if [[ "$just_close" == "true" ]]; then
  exit 0
fi

open_cursor_on() {
  local bin=""
  if command -v cursor >/dev/null 2>&1; then
    bin="$(command -v cursor)"
  elif [[ -x /usr/bin/cursor ]]; then
    bin=/usr/bin/cursor
  else
    echo "workin: cursor not found" >&2
    return 1
  fi
  log "opening Cursor: $1"
  if command -v setsid >/dev/null 2>&1; then
    setsid "$bin" "$1" </dev/null >/dev/null 2>&1 &
  else
    nohup "$bin" "$1" </dev/null >/dev/null 2>&1 &
  fi
}

open_terminal_on() {
  local dir="$1"
  [[ -d "$dir" ]] || dir="$(dirname "$dir")"
  log "opening terminal: $dir"
  if command -v gnome-terminal >/dev/null 2>&1; then
    if command -v setsid >/dev/null 2>&1; then
      setsid gnome-terminal --working-directory="$dir" </dev/null >/dev/null 2>&1 &
    else
      nohup gnome-terminal --working-directory="$dir" </dev/null >/dev/null 2>&1 &
    fi
    return 0
  fi
  if command -v x-terminal-emulator >/dev/null 2>&1; then
    (cd "$dir" && setsid x-terminal-emulator </dev/null >/dev/null 2>&1 &) || true
    return 0
  fi
  echo "workin: no terminal emulator found" >&2
  return 1
}

open_browser_on() {
  local chrome="" c
  for c in /usr/bin/google-chrome-stable /usr/bin/google-chrome /opt/google/chrome/google-chrome /usr/bin/chromium; do
    if [[ -x "$c" ]]; then
      chrome="$c"
      break
    fi
  done
  if [[ -z "$chrome" ]]; then
    echo "workin: Chrome not found" >&2
    return 1
  fi
  local url="$1"
  if [[ "$url" != http://* && "$url" != https://* && "$url" != file://* ]]; then
    if [[ -d "$url" ]]; then
      url="file://${url}/"
    else
      url="file://${url}"
    fi
  fi
  log "opening Chrome: $url"
  if command -v setsid >/dev/null 2>&1; then
    setsid "$chrome" --new-window "$url" </dev/null >/dev/null 2>&1 &
  else
    nohup "$chrome" --new-window "$url" </dev/null >/dev/null 2>&1 &
  fi
}

if [[ "$open_cursor" == "true" ]]; then
  open_cursor_on "$target"
  sleep "$launch_delay"
fi
if [[ "$open_terminal" == "true" ]]; then
  open_terminal_on "$target"
  sleep "$launch_delay"
fi
if [[ "$open_browser" == "true" ]]; then
  open_browser_on "$target"
fi

log "done ($target)"

