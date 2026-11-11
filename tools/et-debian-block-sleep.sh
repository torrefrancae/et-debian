#!/usr/bin/env bash
# Hold a sleep inhibitor forever so nothing (GNOME, Sleep key, idle) can
# suspend/hibernate except the scheduled et-debian-sleep path, which stops
# this unit before calling rtcwake.
set -euo pipefail
exec /usr/bin/systemd-inhibit \
  --what=sleep:idle \
  --who=et-debian \
  --why='only et-debian-sleep.timer (06:00) may suspend' \
  --mode=block \
  /bin/sleep infinity
