#!/usr/bin/env bash
# Session helper: kill fake X/GNOME blank (black + blinking cursor) and keep the
# *physical* panel powered off while working over xrdp. Do not turn the lid
# panel back on when the RDP session is active — that was lighting the laptop.
set -euo pipefail

log() { printf '[et-debian-display] %s\n' "$*" >&2; }

# Kill GNOME's fake black blank in this session (causes blinking cursor on xrdp).
if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
  gsettings set org.gnome.desktop.screensaver idle-activation-enabled false 2>/dev/null || true
  gsettings set org.gnome.settings-daemon.plugins.power idle-dim false 2>/dev/null || true
fi

# xorgxrdp has no DPMS — never enable a software blank here.
if command -v xset >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
  xset s off 2>/dev/null || true
  xset s noblank 2>/dev/null || true
  xset -dpms 2>/dev/null || true
  log "X blank/DPMS disabled on DISPLAY=${DISPLAY}"
fi

PANEL_OFF=/usr/local/sbin/et-debian-panel-off
# Assert once at login, then every 30s (systemd timer also re-asserts).
while true; do
  if [[ -x "${PANEL_OFF}" ]]; then
    sudo -n "${PANEL_OFF}" 2>/dev/null || true
  fi
  sleep 30
done
