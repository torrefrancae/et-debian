#!/usr/bin/env bash
# System-wide idle watcher (root via systemd).
# - 5 minutes with no keyboard/mouse (evdev) → physical panel off
# - On input → panel on + reset X idle (avoids login flash then black+cursor)
# Never suspends — only et-debian-sleep.timer (06:00) does that.
set -euo pipefail

BLANK_SECS="${ET_DEBIAN_SCREEN_BLANK_SECS:-300}"
POLL="${ET_DEBIAN_IDLE_POLL_SECS:-2}"
PANEL_OFF=/usr/local/sbin/et-debian-panel-off
PANEL_ON=/usr/local/sbin/et-debian-panel-on
STATE_DIR=/run/et-debian
ACT_FILE="${STATE_DIR}/last-input-epoch"
off=0
last_seen=0
grace_until=0

log() { logger -t et-debian-display "$*"; printf '[et-debian-display] %s\n' "$*"; }

mkdir -p "${STATE_DIR}"
printf '%s\n' "$(date +%s)" >"${ACT_FILE}.tmp"
mv -f "${ACT_FILE}.tmp" "${ACT_FILE}"
last_seen="$(tr -d '[:space:]' <"${ACT_FILE}")"

# Background: watch evdev for KEY/REL/ABS; atomically update ACT_FILE.
python3 - <<'PY' &
import os, struct, select, time, glob, tempfile
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

def stamp():
    now = str(int(time.time()))
    d = os.path.dirname(act)
    fd, tmp = tempfile.mkstemp(prefix="act-", dir=d)
    try:
        os.write(fd, (now + "\n").encode())
        os.close(fd)
        os.rename(tmp, act)
    except Exception:
        try:
            os.close(fd)
        except Exception:
            pass
        try:
            os.unlink(tmp)
        except Exception:
            pass

while True:
    r, _, _ = select.select(fds, [], [], 60.0)
    hit = False
    for fd in r:
        try:
            data = os.read(fd, size * 64)
        except (BlockingIOError, OSError):
            continue
        for i in range(0, len(data) - size + 1, size):
            _, _, typ, _, val = struct.unpack_from(fmt, data, i)
            # KEY down/up (val 0/1/2), any REL/ABS
            if typ in want:
                hit = True
                break
        if hit:
            break
    if hit:
        stamp()
PY
EVDEV_PID=$!
trap 'kill "${EVDEV_PID}" 2>/dev/null || true' EXIT

read_act() {
  tr -d '[:space:]' <"${ACT_FILE}" 2>/dev/null || date +%s
}

wake_x() {
  # Reset X idle + unblank so GNOME greeter does not paint once then go black+cursor.
  local gxa disp
  if [[ -S /tmp/.X11-unix/X0 ]]; then
    gxa=/run/user/112/gdm/Xauthority
    [[ -e "${gxa}" ]] || gxa="$(ls /run/user/*/gdm/Xauthority 2>/dev/null | head -1 || true)"
    if [[ -n "${gxa:-}" && -e "${gxa}" ]]; then
      DISPLAY=:0 XAUTHORITY="${gxa}" xset dpms force on 2>/dev/null || true
      DISPLAY=:0 XAUTHORITY="${gxa}" xset s reset -dpms s off s noblank 2>/dev/null || true
      # Synthetic motion resets X's internal idle counter (space alone often does not).
      DISPLAY=:0 XAUTHORITY="${gxa}" xdotool mousemove_relative -- 1 0 mousemove_relative -- -1 0 2>/dev/null || true
      DISPLAY=:0 XAUTHORITY="${gxa}" dbus-send --session --dest=org.gnome.ScreenSaver \
        --type=method_call /org/gnome/ScreenSaver org.gnome.ScreenSaver.SetActive boolean:false 2>/dev/null || true
    fi
  fi
  for disp in :10 :11; do
    [[ -S /tmp/.X11-unix/X${disp#:} ]] || continue
    [[ -e /home/et/.Xauthority ]] || continue
    DISPLAY="${disp}" XAUTHORITY=/home/et/.Xauthority xset dpms force on 2>/dev/null || true
    DISPLAY="${disp}" XAUTHORITY=/home/et/.Xauthority xset s reset -dpms s off s noblank 2>/dev/null || true
    DISPLAY="${disp}" XAUTHORITY=/home/et/.Xauthority xdotool mousemove_relative -- 1 0 mousemove_relative -- -1 0 2>/dev/null || true
  done
}

idle_secs() {
  local now last
  now="$(date +%s)"
  last="$(read_act)"
  # Guard corrupt/concatenated stamps
  [[ "${last}" =~ ^[0-9]{9,12}$ ]] || last="${now}"
  echo $(( now - last ))
}

log "system idle panel watcher start (blank=${BLANK_SECS}s, evdev+X-idle-reset)"

while true; do
  seen="$(read_act)"
  [[ "${seen}" =~ ^[0-9]{9,12}$ ]] || seen="$(date +%s)"
  now="$(date +%s)"
  idle="$(idle_secs)"

  if (( seen > last_seen )); then
    if [[ "${off}" -eq 1 ]]; then
      "${PANEL_ON}" >/dev/null 2>&1 || true
      off=0
      log "panel on (input, was blank; idle_stamp=${idle}s)"
    fi
    wake_x
    # Do not re-blank for a short grace window after input (covers greeter redraw).
    grace_until=$(( now + 15 ))
    last_seen="${seen}"
  fi

  if (( now >= grace_until && idle >= BLANK_SECS )); then
    if [[ "${off}" -eq 0 ]]; then
      "${PANEL_OFF}" >/dev/null 2>&1 || true
      off=1
      log "panel off (idle ${idle}s)"
    fi
  fi

  sleep "${POLL}"
done
