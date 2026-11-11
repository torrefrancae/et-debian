#!/usr/bin/env bash
# Move the pointer in a circle around the middle of the screen.
# Each INTERVAL seconds advances ~STEP_PX along the arc (defaults: 20s, 5px).
#
# Usage:
#   mouse-circle
#   mouse-circle --radius=80 --step=5 --interval=20
#   mouse-circle --once
#   mouse-circle --duration=60
#   mouse-circle --minutes=50
#   MOUSE_CIRCLE_DISPLAY=:10 mouse-circle
set -euo pipefail

RADIUS=80
STEP_PX=5
INTERVAL=20
DURATION=0
ONCE=0

usage() {
  cat <<'EOF'
Usage: mouse-circle [--radius=N] [--step=N] [--interval=N] [--duration=N] [--minutes=N] [--once] [--help]

  --radius=N    Circle radius in pixels (default 80)
  --step=N      Arc distance per move in pixels (default 5)
  --interval=N  Seconds between moves (default 20)
  --duration=N  Stop after N seconds (0 = forever)
  --minutes=N   Stop after N minutes (sets duration to N*60)
  --once        Stop after one full lap
EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --radius=*) RADIUS="${arg#--radius=}" ;;
    --step=*) STEP_PX="${arg#--step=}" ;;
    --interval=*) INTERVAL="${arg#--interval=}" ;;
    --duration=*) DURATION="${arg#--duration=}" ;;
    --minutes=*)
      _MINUTES="${arg#--minutes=}"
      [[ "$_MINUTES" =~ ^[0-9]+$ ]] || {
        echo "mouse-circle: --minutes must be an integer" >&2
        exit 1
      }
      DURATION=$((_MINUTES * 60))
      ;;
    --once) ONCE=1 ;;
    *)
      echo "mouse-circle: unknown option: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[[ "$INTERVAL" =~ ^[0-9]+$ && "$INTERVAL" -gt 0 ]] || {
  echo "mouse-circle: --interval must be an integer > 0" >&2
  exit 1
}

if ! command -v xdotool >/dev/null 2>&1; then
  echo "mouse-circle: xdotool is missing (apt install xdotool)" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "mouse-circle: python3 is missing" >&2
  exit 1
fi

_pick_display() {
  if [[ -n "${MOUSE_CIRCLE_DISPLAY:-}" ]]; then
    printf '%s\n' "$MOUSE_CIRCLE_DISPLAY"
    return 0
  fi
  if [[ -n "${DISPLAY:-}" ]]; then
    printf '%s\n' "$DISPLAY"
    return 0
  fi
  local sid name type display remote seat best="" fallback=""
  while IFS= read -r sid; do
    [[ -n "$sid" ]] || continue
    name="$(loginctl show-session "$sid" -p Name --value 2>/dev/null || true)"
    [[ "$name" == "$(id -un)" ]] || continue
    type="$(loginctl show-session "$sid" -p Type --value 2>/dev/null || true)"
    display="$(loginctl show-session "$sid" -p Display --value 2>/dev/null || true)"
    remote="$(loginctl show-session "$sid" -p Remote --value 2>/dev/null || true)"
    seat="$(loginctl show-session "$sid" -p Seat --value 2>/dev/null || true)"
    [[ "$type" == "x11" && -n "$display" ]] || continue
    # Prefer xrdp/remote session for lab use; else first local X11.
    if [[ "$remote" == "yes" || "$seat" != "seat0" ]]; then
      best="$display"
      break
    fi
    [[ -n "$fallback" ]] || fallback="$display"
  done < <(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}')
  if [[ -n "$best" ]]; then
    printf '%s\n' "$best"
    return 0
  fi
  if [[ -n "$fallback" ]]; then
    printf '%s\n' "$fallback"
    return 0
  fi
  return 1
}

DISPLAY_VAL="$(_pick_display)" || {
  echo "mouse-circle: no X11 display for $(id -un); set DISPLAY or MOUSE_CIRCLE_DISPLAY" >&2
  exit 1
}
export DISPLAY="$DISPLAY_VAL"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

export MOUSE_CIRCLE_RADIUS="$RADIUS"
export MOUSE_CIRCLE_STEP="$STEP_PX"
export MOUSE_CIRCLE_INTERVAL="$INTERVAL"
export MOUSE_CIRCLE_DURATION="$DURATION"
export MOUSE_CIRCLE_ONCE="$ONCE"

printf 'mouse-circle: DISPLAY=%s radius=%s step=%s interval=%ss\n' \
  "$DISPLAY" "$RADIUS" "$STEP_PX" "$INTERVAL" >&2

# Keep this bash process so pgrep/pkill -f mouse-circle still matches.
python3 - <<'PY'
import math
import os
import signal
import subprocess
import sys
import time

radius = float(os.environ["MOUSE_CIRCLE_RADIUS"])
step = float(os.environ["MOUSE_CIRCLE_STEP"])
interval = float(os.environ["MOUSE_CIRCLE_INTERVAL"])
duration = float(os.environ["MOUSE_CIRCLE_DURATION"])
once = os.environ.get("MOUSE_CIRCLE_ONCE", "0") == "1"

if radius <= 0 or step <= 0:
    print("mouse-circle: radius and step must be > 0", file=sys.stderr)
    sys.exit(1)
if interval <= 0:
    print("mouse-circle: interval must be > 0", file=sys.stderr)
    sys.exit(1)

geom = subprocess.check_output(["xdotool", "getdisplaygeometry"], text=True).strip().split()
width, height = int(geom[0]), int(geom[1])
cx, cy = width / 2.0, height / 2.0

omega = step / radius
stop = {"flag": False}

def _stop(*_args):
    stop["flag"] = True

signal.signal(signal.SIGINT, _stop)
signal.signal(signal.SIGTERM, _stop)

def _fmt_left(seconds: float) -> str:
    left = max(0, int(math.ceil(seconds)))
    m, s = divmod(left, 60)
    h, m = divmod(m, 60)
    if h:
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m}:{s:02d}"

start = time.monotonic()
angle = 0.0
laps = 0

while not stop["flag"]:
    elapsed = time.monotonic() - start
    if duration > 0 and elapsed >= duration:
        break
    x = int(round(cx + radius * math.cos(angle)))
    y = int(round(cy + radius * math.sin(angle)))
    x = max(0, min(width - 1, x))
    y = max(0, min(height - 1, y))
    subprocess.run(["xdotool", "mousemove", "--sync", str(x), str(y)], check=False)
    if duration > 0:
        print(f"{x},{y}  left={_fmt_left(duration - elapsed)}", flush=True)
    else:
        print(f"{x},{y}", flush=True)
    remaining_sleep = interval
    if duration > 0:
        remaining_sleep = min(interval, max(0.0, duration - (time.monotonic() - start)))
    if remaining_sleep <= 0:
        break
    time.sleep(remaining_sleep)
    angle += omega
    if angle >= 2.0 * math.pi:
        angle -= 2.0 * math.pi
        laps += 1
        if once:
            break

if stop["flag"]:
    print("stop", flush=True)
elif duration > 0:
    print("0:00", flush=True)
else:
    print("done", flush=True)
PY
