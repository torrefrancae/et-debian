#!/usr/bin/env bash
# Idle → physical panel off (DRM/backlight). Activity → panel on.
# Does NOT suspend the machine. System sleep is only et-debian-sleep.timer (06:00).
# Default blank: 5 minutes (ET_DEBIAN_SCREEN_BLANK_SECS).
#
# Disable GNOME's fake black blank (blinking cursor). xorgxrdp has no DPMS, so
# we always drive the laptop eDP via et-debian-panel-off/on.
set -euo pipefail

BLANK_SECS="${ET_DEBIAN_SCREEN_BLANK_SECS:-300}"
BLANK_MS=$((BLANK_SECS * 1000))
POLL="${ET_DEBIAN_IDLE_POLL_SECS:-5}"

log() { printf '[et-debian-display] %s\n' "$*" >&2; }

PANEL_OFF=/usr/local/sbin/et-debian-panel-off
PANEL_ON=/usr/local/sbin/et-debian-panel-on
off=0

# Kill GNOME fake blank / idle-dim in this session when possible.
if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
  gsettings set org.gnome.desktop.screensaver idle-activation-enabled false 2>/dev/null || true
  gsettings set org.gnome.settings-daemon.plugins.power idle-dim false 2>/dev/null || true
  gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type nothing 2>/dev/null || true
  gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type nothing 2>/dev/null || true
fi

# Never use software blank on this X display (especially xrdp).
if command -v xset >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
  xset s off 2>/dev/null || true
  xset s noblank 2>/dev/null || true
  xset -dpms 2>/dev/null || true
fi

command -v xprintidle >/dev/null 2>&1 || {
  log "xprintidle missing — idle panel loop disabled"
  exit 0
}
[[ -x "${PANEL_OFF}" && -x "${PANEL_ON}" ]] || {
  log "panel helpers missing — idle panel loop disabled"
  exit 0
}

log "idle panel-off after ${BLANK_SECS}s (poll ${POLL}s) on DISPLAY=${DISPLAY:-?}"

while true; do
  idle="$(xprintidle 2>/dev/null || echo 0)"
  if (( idle >= BLANK_MS )); then
    if [[ "${off}" -eq 0 ]]; then
      if sudo -n "${PANEL_OFF}" 2>/dev/null; then
        off=1
        log "panel off (idle ${idle}ms)"
      fi
    fi
  else
    if [[ "${off}" -eq 1 ]]; then
      if sudo -n "${PANEL_ON}" 2>/dev/null; then
        off=0
        log "panel on (activity, idle ${idle}ms)"
      fi
    fi
  fi
  sleep "${POLL}"
done
