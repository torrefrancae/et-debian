#!/usr/bin/env bash
# System-wide idle watcher (root via systemd).
# - After 5 minutes with no keyboard/mouse activity → physical panel off
# - On any key/mouse activity → panel on + wake local X (fixes black+cursor)
# Uses /dev/input (evdev), not only xprintidle — X idle can stick after suspend.
# Never suspends — only et-debian-sleep.timer does that at 06:00.
set -euo pipefail

BLANK_SECS="${ET_DEBIAN_SCREEN_BLANK_SECS:-300}"
POLL="${ET_DEBIAN_IDLE_POLL_SECS:-2}"
PANEL_OFF=/usr/local/sbin/et-debian-panel-off
PANEL_ON=/usr/local/sbin/et-debian-panel-on
STATE_DIR=/run/et-debian
ACT_FILE="${STATE_DIR}/last-input-epoch"
off=0
last_seen=0

log() { logger -t et-debian-display "$*"; printf '[et-debian-display] %s\n' "$*"; }

mkdir -p "${STATE_DIR}"
date +%s >"${ACT_FILE}"
last_seen="$(cat "${ACT_FILE}")"

# Background: watch evdev for KEY/REL/ABS activity.
python3 - <<'PY' &
import os, struct, select, time, glob
act = "/run/et-debian/last-input-epoch"
fmt = "llHHI"
size = struct.calcsize(fmt)
want = {1, 2, 3}  # EV_KEY, EV_REL, EV_ABS
fds = []
for path in sorted(glob.glob("/dev/input/event*")):
    try:
        fds.append(os.open(path, os.O_RDONLY | os.O_NONBLOCK))
    except OSError:
        pass
if not fds:
    raise SystemExit(0)
while True:
    r, _, _ = select.select(fds, [], [], 60.0)
    for fd in r:
        try:
            data = os.read(fd, size * 64)
        except (BlockingIOError, OSError):
            continue
        hit = False
        for i in range(0, len(data) - size + 1, size):
            _, _, typ, _, _ = struct.unpack_from(fmt, data, i)
            if typ in want:
                hit = True
                break
        if hit:
            try:
                with open(act, "w", encoding="utf-8") as f:
                    f.write(str(int(time.time())))
            except OSError:
                pass
PY
EVDEV_PID=$!
trap 'kill "${EVDEV_PID}" 2>/dev/null || true' EXIT

wake_x() {
  local gxa disp
  if [[ -S /tmp/.X11-unix/X0 ]]; then
    gxa=/run/user/112/gdm/Xauthority
    [[ -e "${gxa}" ]] || gxa="$(ls /run/user/*/gdm/Xauthority 2>/dev/null | head -1 || true)"
    if [[ -n "${gxa:-}" && -e "${gxa}" ]]; then
      DISPLAY=:0 XAUTHORITY="${gxa}" xset dpms force on 2>/dev/null || true
      DISPLAY=:0 XAUTHORITY="${gxa}" xset s reset -dpms s off s noblank 2>/dev/null || true
    fi
  fi
  for disp in :10 :11; do
    [[ -S /tmp/.X11-unix/X${disp#:} ]] || continue
    [[ -e /home/et/.Xauthority ]] || continue
    DISPLAY="${disp}" XAUTHORITY=/home/et/.Xauthority xset dpms force on 2>/dev/null || true
    DISPLAY="${disp}" XAUTHORITY=/home/et/.Xauthority xset s reset -dpms s off s noblank 2>/dev/null || true
  done
}

idle_secs() {
  local now last
  now="$(date +%s)"
  last="$(cat "${ACT_FILE}" 2>/dev/null || echo "${now}")"
  echo $(( now - last ))
}

log "system idle panel watcher start (blank=${BLANK_SECS}s, evdev activity)"

while true; do
  seen="$(cat "${ACT_FILE}" 2>/dev/null || echo 0)"
  idle="$(idle_secs)"

  if (( seen > last_seen )); then
    # Fresh keyboard/mouse activity
    if [[ "${off}" -eq 1 ]]; then
      "${PANEL_ON}" >/dev/null 2>&1 || true
      off=0
      log "panel on (input activity, was idle ${idle}s)"
    fi
    wake_x
    last_seen="${seen}"
  fi

  if (( idle >= BLANK_SECS )); then
    if [[ "${off}" -eq 0 ]]; then
      "${PANEL_OFF}" >/dev/null 2>&1 || true
      off=1
      log "panel off (idle ${idle}s)"
    fi
  fi

  sleep "${POLL}"
done
