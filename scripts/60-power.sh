#!/usr/bin/env bash
# Host power policy:
#  - no idle / lid auto-suspend
#  - sleep 06:00 / wake 15:00 via rtcwake + systemd timer
#  - enable RTC alarm wake from Debian (sysfs + ACPI)
# No Docker.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

log "power policy (no idle sleep; schedule 06:00 → 15:00) + RTC wake"
apt_update
apt_install util-linux dconf-cli libglib2.0-bin

as_root install -d /usr/local/sbin /etc/systemd/system
as_root install -m 0755 \
  "${REPO_ROOT}/tools/et-debian-sleep-until-wake.sh" \
  /usr/local/sbin/et-debian-sleep-until-wake
as_root install -m 0755 \
  "${REPO_ROOT}/tools/et-debian-enable-rtc-wake.sh" \
  /usr/local/sbin/et-debian-enable-rtc-wake
as_root install -m 0755 \
  "${REPO_ROOT}/tools/et-debian-disable-idle-sleep.sh" \
  /usr/local/sbin/et-debian-disable-idle-sleep
as_root install -m 0644 \
  "${REPO_ROOT}/conf/systemd/et-debian-sleep.service" \
  /etc/systemd/system/et-debian-sleep.service
as_root install -m 0644 \
  "${REPO_ROOT}/conf/systemd/et-debian-sleep.timer" \
  /etc/systemd/system/et-debian-sleep.timer
as_root install -m 0644 \
  "${REPO_ROOT}/conf/systemd/et-debian-rtc-wake.service" \
  /etc/systemd/system/et-debian-rtc-wake.service
as_root install -m 0644 \
  "${REPO_ROOT}/conf/systemd/et-debian-no-idle-sleep.service" \
  /etc/systemd/system/et-debian-no-idle-sleep.service

# Keep wall clock honest so OnCalendar fires at real 06:00
as_root timedatectl set-ntp true || true

# Disable idle/lid suspend first (does not mask suspend.target)
as_root /usr/local/sbin/et-debian-disable-idle-sleep

# Flip kernel/ACPI RTC wake on now; service re-asserts on boot/before sleep
as_root /usr/local/sbin/et-debian-enable-rtc-wake

as_root systemctl daemon-reload
as_root systemctl enable --now et-debian-no-idle-sleep.service || true
as_root systemctl enable --now et-debian-sleep.timer
as_root systemctl enable --now et-debian-rtc-wake.service || true

log "timer status:"
as_root systemctl list-timers et-debian-sleep.timer --no-pager || true
log "skip overnight sleep: sudo touch /etc/et-debian-nosleep"
log "dry-run: sudo ET_DEBIAN_SLEEP_DRY=1 /usr/local/sbin/et-debian-sleep-until-wake"
log "power schedule done"
