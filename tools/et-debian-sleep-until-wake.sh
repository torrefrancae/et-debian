#!/usr/bin/env bash
# Suspend the host until the next wake time (default 15:00 local).
# Invoked by et-debian-sleep.timer at 06:00. No Docker.
set -euo pipefail

WAKE_HOUR="${ET_DEBIAN_WAKE_HOUR:-15}"       # 3pm
WAKE_MIN="${ET_DEBIAN_WAKE_MIN:-0}"
HOLD_FILE="${ET_DEBIAN_NOSLEEP_FILE:-/etc/et-debian-nosleep}"
MODE="${ET_DEBIAN_SLEEP_MODE:-mem}"          # mem = S3/s2idle via rtcwake

log() { logger -t et-debian-sleep "$*"; printf '[et-debian-sleep] %s\n' "$*"; }

if [[ -f "${HOLD_FILE}" ]]; then
  log "hold file ${HOLD_FILE} present — staying awake"
  exit 0
fi

if [[ "${EUID}" -ne 0 ]]; then
  log "must run as root"
  exit 1
fi

if ! command -v rtcwake >/dev/null 2>&1; then
  log "rtcwake missing — install util-linux"
  exit 1
fi

# Re-assert OS-side RTC wake enables right before sleep
if [[ -x /usr/local/sbin/et-debian-enable-rtc-wake ]]; then
  /usr/local/sbin/et-debian-enable-rtc-wake || true
fi

# Next WAKE_HOUR:WAKE_MIN local.
now_epoch="$(date +%s)"
wake_today="$(date -d "today ${WAKE_HOUR}:${WAKE_MIN}:00" +%s)"
if (( now_epoch >= wake_today )); then
  wake_epoch="$(date -d "tomorrow ${WAKE_HOUR}:${WAKE_MIN}:00" +%s)"
else
  wake_epoch="${wake_today}"
fi

wake_human="$(date -d "@${wake_epoch}" '+%F %T %Z')"
log "arm RTC wake for ${wake_human} (epoch ${wake_epoch}), then suspend mode=${MODE}"

# Clear any previous alarm, then let rtcwake set it.
echo 0 >/sys/class/rtc/rtc0/wakealarm 2>/dev/null || true
sync

if [[ "${ET_DEBIAN_SLEEP_DRY:-0}" == "1" ]]; then
  log "DRY RUN — would: rtcwake -m ${MODE} -t ${wake_epoch}"
  rtcwake -m show || true
  echo -n "rtc0 wakeup="; cat /sys/class/rtc/rtc0/device/power/wakeup 2>/dev/null || cat /sys/class/rtc/rtc0/power/wakeup 2>/dev/null || echo "?"
  grep -E 'RTC|ALARM|PNP0B' /proc/acpi/wakeup 2>/dev/null || true
  exit 0
fi

exec rtcwake -m "${MODE}" -t "${wake_epoch}"
