#!/usr/bin/env bash
# Host power policy:
#  - no idle / lid auto-suspend (only 06:00 rtcwake → wake 15:00)
#  - physical panel off after 5 minutes idle; on again on activity
#  - no fake black screensaver (blinking cursor)
#  - RTC wake enable
# No Docker.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

log "power policy (5m idle panel-off; schedule 06:00 → 15:00) + RTC wake"
apt_update
apt_install util-linux dconf-cli libglib2.0-bin xprintidle x11-xserver-utils

as_root install -d /usr/local/sbin /usr/local/bin /etc/systemd/system /var/lib/et-debian
as_root install -m 0755 \
  "${REPO_ROOT}/tools/et-debian-sleep-until-wake.sh" \
  /usr/local/sbin/et-debian-sleep-until-wake
as_root install -m 0755 \
  "${REPO_ROOT}/tools/et-debian-enable-rtc-wake.sh" \
  /usr/local/sbin/et-debian-enable-rtc-wake
as_root install -m 0755 \
  "${REPO_ROOT}/tools/et-debian-disable-idle-sleep.sh" \
  /usr/local/sbin/et-debian-disable-idle-sleep
as_root install -m 0755 \
  "${REPO_ROOT}/tools/et-debian-panel-off.sh" \
  /usr/local/sbin/et-debian-panel-off
as_root install -m 0755 \
  "${REPO_ROOT}/tools/et-debian-panel-on.sh" \
  /usr/local/sbin/et-debian-panel-on
as_root install -m 0755 \
  "${REPO_ROOT}/tools/et-debian-display-idle-system.sh" \
  /usr/local/sbin/et-debian-display-idle-system
as_root install -m 0755 \
  "${REPO_ROOT}/tools/et-debian-display-idle-off.sh" \
  /usr/local/bin/et-debian-display-idle-off

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
as_root install -m 0644 \
  "${REPO_ROOT}/conf/systemd/et-debian-display-idle.service" \
  /etc/systemd/system/et-debian-display-idle.service

# Legacy aggressive keep-off (boot + every 30s) — remove if present
as_root systemctl disable --now et-debian-panel-keep-off.timer 2>/dev/null || true
as_root systemctl disable --now et-debian-panel-off.service 2>/dev/null || true
as_root rm -f \
  /etc/systemd/system/et-debian-panel-keep-off.timer \
  /etc/systemd/system/et-debian-panel-keep-off.service \
  /etc/systemd/system/et-debian-panel-off.service \
  /usr/local/sbin/et-debian-panel-keep-off \
  /var/lib/et-debian/panel-keep-on \
  2>/dev/null || true

as_root timedatectl set-ntp true || true

as_root /usr/local/sbin/et-debian-disable-idle-sleep
as_root /usr/local/sbin/et-debian-enable-rtc-wake

# Optional per-session helper (system service is the source of truth)
if id et >/dev/null 2>&1 && [[ -f "${REPO_ROOT}/conf/xdg/display-idle-off.desktop" ]]; then
  home="$(getent passwd et | cut -d: -f6)"
  as_root install -d -o et -g et "${home}/.config/autostart"
  as_root install -m 0644 -o et -g et \
    "${REPO_ROOT}/conf/xdg/display-idle-off.desktop" \
    "${home}/.config/autostart/display-idle-off.desktop"
fi

as_root systemctl daemon-reload
as_root systemctl enable --now et-debian-no-idle-sleep.service || true
as_root systemctl enable --now et-debian-display-idle.service || true
as_root systemctl enable --now et-debian-sleep.timer
as_root systemctl enable --now et-debian-rtc-wake.service || true

log "timer status:"
as_root systemctl list-timers et-debian-sleep.timer --no-pager || true
as_root systemctl is-active et-debian-display-idle.service || true
log "policy: panel off after 5m idle; system sleep only at 06:00 (wake 15:00)"
log "power schedule done"
