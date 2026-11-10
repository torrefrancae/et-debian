#!/usr/bin/env bash
# Host sleep 06:00 / wake 15:00 via rtcwake + systemd timer. No Docker.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

log "power schedule (sleep 06:00 → wake 15:00)"
apt_update
apt_install util-linux

as_root install -d /usr/local/sbin /etc/systemd/system
as_root install -m 0755 \
  "${REPO_ROOT}/tools/et-debian-sleep-until-wake.sh" \
  /usr/local/sbin/et-debian-sleep-until-wake
as_root install -m 0644 \
  "${REPO_ROOT}/conf/systemd/et-debian-sleep.service" \
  /etc/systemd/system/et-debian-sleep.service
as_root install -m 0644 \
  "${REPO_ROOT}/conf/systemd/et-debian-sleep.timer" \
  /etc/systemd/system/et-debian-sleep.timer

# Keep wall clock honest so OnCalendar fires at real 06:00
as_root timedatectl set-ntp true || true

as_root systemctl daemon-reload
as_root systemctl enable --now et-debian-sleep.timer

log "timer status:"
as_root systemctl list-timers et-debian-sleep.timer --no-pager || true
log "skip overnight sleep anytime with: sudo touch /etc/et-debian-nosleep"
log "dry-run once: sudo ET_DEBIAN_SLEEP_DRY=1 /usr/local/sbin/et-debian-sleep-until-wake"
log "power schedule done"
