#!/usr/bin/env bash
# Host power policy:
#  - no idle / lid auto-suspend (only 06:00 rtcwake)
#  - no fake black screensaver; physical panel real-off via DRM/backlight
#  - RTC wake enable
# No Docker.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

log "power policy (panel real-off; schedule 06:00 → 15:00) + RTC wake"
apt_update
apt_install util-linux dconf-cli libglib2.0-bin xprintidle x11-xserver-utils

as_root install -d /usr/local/sbin /usr/local/bin /etc/systemd/system
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
  "${REPO_ROOT}/conf/systemd/et-debian-panel-off.service" \
  /etc/systemd/system/et-debian-panel-off.service

as_root timedatectl set-ntp true || true

as_root /usr/local/sbin/et-debian-disable-idle-sleep
as_root /usr/local/sbin/et-debian-enable-rtc-wake

# Autostart idle→panel-off helper for et
if id et >/dev/null 2>&1 && [[ -f "${REPO_ROOT}/conf/xdg/display-idle-off.desktop" ]]; then
  home="$(getent passwd et | cut -d: -f6)"
  as_root install -d -o et -g et "${home}/.config/autostart"
  as_root install -m 0644 -o et -g et \
    "${REPO_ROOT}/conf/xdg/display-idle-off.desktop" \
    "${home}/.config/autostart/display-idle-off.desktop"
fi

as_root systemctl daemon-reload
as_root systemctl enable --now et-debian-no-idle-sleep.service || true
as_root systemctl enable --now et-debian-panel-off.service || true
as_root systemctl enable --now et-debian-sleep.timer
as_root systemctl enable --now et-debian-rtc-wake.service || true

# Power the laptop lid panel off now (RDP keeps the machine usable)
as_root /usr/local/sbin/et-debian-panel-off || true

log "timer status:"
as_root systemctl list-timers et-debian-sleep.timer --no-pager || true
log "panel on again: sudo et-debian-panel-on"
log "power schedule done"
