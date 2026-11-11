#!/usr/bin/env bash
# Real panel power management while the machine stays awake.
#
# Idle 5 minutes (keyboard/mouse only — ignore ABS sensors) → DRM/backlight OFF.
# While blanked, re-assert OFF every poll so GNOME cannot leave "black + lights".
# Any key/mouse → panel ON + wake/repair the GDM greeter UI.
#
# System sleep is NOT done here — only et-debian-sleep.timer (06:00).
set -euo pipefail

BLANK_SECS="${ET_DEBIAN_SCREEN_BLANK_SECS:-300}"
POLL="${ET_DEBIAN_IDLE_POLL_SECS:-2}"
PANEL_OFF=/usr/local/sbin/et-debian-panel-off
PANEL_ON=/usr/local/sbin/et-debian-panel-on
STATE_DIR=/run/et-debian
ACT_FILE="${STATE_DIR}/last-input-epoch"
blanked=0
last_seen=0
grace_until=0

log() { logger -t et-debian-display "$*"; printf '[et-debian-display] %s\n' "$*"; }

mkdir -p "${STATE_DIR}"
printf '%s\n' "$(date +%s)" >"${ACT_FILE}.tmp"
mv -f "${ACT_FILE}.tmp" "${ACT_FILE}"
last_seen="$(tr -d '[:space:]' <"${ACT_FILE}")"

# Evdev watcher: KEY and REL only. ABS (accel/lid/touchpad noise) ignored.
python3 - <<'PY' &
import os, struct, select, time, glob, tempfile
act = "/run/et-debian/last-input-epoch"
fmt = "llHHI"
size = struct.calcsize(fmt)
EV_KEY, EV_REL = 1, 2
fds = []
for path in sorted(glob.glob("/dev/input/event*")):
    # Skip known non-user devices by name when possible
    name_path = f"/sys/class/input/{os.path.basename(path)}/device/name"
    try:
        name = open(name_path, "r", encoding="utf-8", errors="ignore").read().strip().lower()
    except OSError:
        name = ""
    if any(x in name for x in ("accel", "gyro", "lid", "power", "sleep", "video bus", "hd audio", "pcspkr", "intel hid")):
        continue
    try:
        fds.append(os.open(path, os.O_RDONLY | os.O_NONBLOCK))
    except OSError:
        pass
if not fds:
    raise SystemExit(0)

def stamp():
    now = str(int(time.time())) + "\n"
    fd, tmp = tempfile.mkstemp(prefix="act-", dir=os.path.dirname(act))
    try:
        os.write(fd, now.encode())
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
            _, _, typ, code, val = struct.unpack_from(fmt, data, i)
            if typ == EV_KEY and val != 0:  # key/button press or repeat
                hit = True
                break
            if typ == EV_REL and val != 0:  # real mouse movement/wheel
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

panel_is_lit() {
  local bl bp
  bl="$(cat /sys/class/backlight/intel_backlight/brightness 2>/dev/null || echo 0)"
  bp="$(cat /sys/class/backlight/intel_backlight/bl_power 2>/dev/null || echo 0)"
  # lit if brightness > 0 and not powered down
  [[ "${bl}" != "0" && "${bp}" != "4" ]]
}

wake_greeter() {
  local gxa
  gxa=/run/user/112/gdm/Xauthority
  [[ -e "${gxa}" ]] || gxa="$(ls /run/user/*/gdm/Xauthority 2>/dev/null | head -1 || true)"
  [[ -n "${gxa:-}" && -e "${gxa}" && -S /tmp/.X11-unix/X0 ]] || return 0

  # Unblank + reset idle as the greeter user (never as root — that spawned a bad ScreenSaver).
  runuser -u Debian-gdm -- env DISPLAY=:0 XAUTHORITY="${gxa}" \
    xset dpms force on s reset -dpms s off s noblank 2>/dev/null || true
  runuser -u Debian-gdm -- env DISPLAY=:0 XAUTHORITY="${gxa}" \
    xdotool mousemove 960 540 mousemove_relative -- 1 0 mousemove_relative -- -1 0 2>/dev/null || true

  # If X idle is still huge, greeter UI is stuck black — bounce gnome-shell (GDM respawns it).
  local idle_ms
  idle_ms="$(runuser -u Debian-gdm -- env DISPLAY=:0 XAUTHORITY="${gxa}" xprintidle 2>/dev/null || echo 0)"
  if [[ "${idle_ms}" =~ ^[0-9]+$ ]] && (( idle_ms > 5000 )); then
    log "greeter X-idle=${idle_ms}ms after wake — restarting gdm gnome-shell"
    pkill -u Debian-gdm -x gnome-shell 2>/dev/null || true
    sleep 2
    runuser -u Debian-gdm -- env DISPLAY=:0 XAUTHORITY="${gxa}" \
      xset dpms force on s reset -dpms s off s noblank 2>/dev/null || true
  fi
}

idle_secs() {
  local now last
  now="$(date +%s)"
  last="$(read_act)"
  [[ "${last}" =~ ^[0-9]{9,12}$ ]] || last="${now}"
  echo $(( now - last ))
}

assert_blank() {
  "${PANEL_OFF}" >/dev/null 2>&1 || true
  # If something turned lights back on without UI, force off again.
  if panel_is_lit; then
    "${PANEL_OFF}" >/dev/null 2>&1 || true
  fi
}

log "idle panel manager start (blank=${BLANK_SECS}s; KEY/REL only; re-assert while blank)"

while true; do
  seen="$(read_act)"
  [[ "${seen}" =~ ^[0-9]{9,12}$ ]] || seen="$(date +%s)"
  now="$(date +%s)"
  idle="$(idle_secs)"

  if (( seen > last_seen )); then
    "${PANEL_ON}" >/dev/null 2>&1 || true
    wake_greeter
    blanked=0
    grace_until=$(( now + 20 ))
    last_seen="${seen}"
    log "panel on (input; idle_stamp=${idle}s)"
  fi

  if (( now >= grace_until && idle >= BLANK_SECS )); then
    assert_blank
    if [[ "${blanked}" -eq 0 ]]; then
      blanked=1
      log "panel off (idle ${idle}s)"
    fi
  elif [[ "${blanked}" -eq 1 ]]; then
    # Stay truly dark until the next key/mouse — fight backlight restore / black+lights.
    assert_blank
  fi

  sleep "${POLL}"
done
