#!/usr/bin/env bash
# Session helper: when user is idle, power off the *physical* panel (real off).
# Disables fake X blank (black + blinking cursor). xorgxrdp has no DPMS.
# Runs as the graphical user via autostart; uses pkexec/sudoers for panel-off.
set -euo pipefail

BLANK_MS="${ET_DEBIAN_SCREEN_BLANK_SECS:-300}"
BLANK_MS=$((BLANK_MS * 1000))
POLL=5

log() { printf '[et-debian-display] %s\n' "$*" >&2; }

# Kill GNOME's fake black blank in this session (causes blinking cursor on xrdp).
if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
  gsettings set org.gnome.desktop.screensaver idle-activation-enabled false 2>/dev/null || true
  gsettings set org.gnome.settings-daemon.plugins.power idle-dim false 2>/dev/null || true
fi

# Prefer real DPMS when the X server supports it (physical seat0).
if command -v xset >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
  if xset q 2>/dev/null | grep -q 'DPMS is Enabled\|Standby:'; then
    secs="${ET_DEBIAN_SCREEN_BLANK_SECS:-300}"
    xset s off 2>/dev/null || true
    xset +dpms 2>/dev/null || true
    xset dpms "${secs}" "${secs}" "${secs}" 2>/dev/null || true
    log "X DPMS timeouts set to ${secs}s"
  else
    log "no X DPMS on DISPLAY=${DISPLAY:-?} (typical for xrdp) — will use DRM panel-off"
  fi
fi

command -v xprintidle >/dev/null 2>&1 || {
  log "xprintidle missing — idle panel-off loop disabled"
  exit 0
}

PANEL_OFF=/usr/local/sbin/et-debian-panel-off
PANEL_ON=/usr/local/sbin/et-debian-panel-on
off=0

while true; do
  idle="$(xprintidle 2>/dev/null || echo 0)"
  if (( idle >= BLANK_MS )); then
    if [[ "${off}" -eq 0 && -x "${PANEL_OFF}" ]]; then
      # passwordless root helper via setuid-free sudoers drop-in or pkexec; try both
      if sudo -n "${PANEL_OFF}" 2>/dev/null; then
        off=1
        log "panel off (idle ${idle}ms)"
      elif pkexec "${PANEL_OFF}" 2>/dev/null; then
        off=1
        log "panel off via pkexec"
      fi
    fi
  else
    if [[ "${off}" -eq 1 && -x "${PANEL_ON}" ]]; then
      sudo -n "${PANEL_ON}" 2>/dev/null || pkexec "${PANEL_ON}" 2>/dev/null || true
      off=0
      log "panel on (activity)"
    fi
  fi
  sleep "${POLL}"
done
