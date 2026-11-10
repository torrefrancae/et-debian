#!/usr/bin/env bash
# Re-assert physical panel power-off. GDM/gsd-power/RDP activity often turns
# eDP backlight back on; this oneshot/timer keeps the lid dark while the box
# stays awake for RDP. Skip when /var/lib/et-debian/panel-keep-on exists.
set -euo pipefail

if [[ -f /var/lib/et-debian/panel-keep-on ]]; then
  exit 0
fi

exec /usr/local/sbin/et-debian-panel-off
