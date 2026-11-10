#!/usr/bin/env bash
# Power off the physical panel (eDP/LVDS) — real display off, machine stays awake.
# Used instead of a fake black screensaver (which leaves a blinking cursor).
# No Docker. Safe to re-run.
set -euo pipefail

log() { logger -t et-debian-panel "$*"; printf '[et-debian-panel] %s\n' "$*"; }

if [[ "${EUID}" -ne 0 ]]; then
  log "must run as root"
  exit 1
fi

off=0
# DRM connector DPMS (best: actually powers the panel down)
for dpms in /sys/class/drm/card*-eDP-*/dpms /sys/class/drm/card*-LVDS-*/dpms; do
  [[ -e "${dpms}" ]] || continue
  echo off >"${dpms}" 2>/dev/null || true
  log "DRM dpms off: ${dpms} -> $(cat "${dpms}" 2>/dev/null || echo '?')"
  off=1
done

# Backlight to 0 as a second belt (some panels ignore connector dpms alone)
mkdir -p /var/lib/et-debian
for bl in /sys/class/backlight/*/brightness; do
  [[ -e "${bl}" ]] || continue
  dir="$(dirname "${bl}")"
  maxf="${dir}/max_brightness"
  cur="$(cat "${bl}" 2>/dev/null || echo 0)"
  # remember last non-zero so panel-on can restore
  if [[ "${cur}" != "0" ]]; then
    echo "${cur}" >"/var/lib/et-debian/backlight-$(basename "${dir}").saved"
  fi
  echo 0 >"${bl}" 2>/dev/null || true
  log "backlight 0: ${bl} (max=$(cat "${maxf}" 2>/dev/null || echo '?'))"
  off=1
done

# Framebuffer blank (console / leftover VTs) — 1=blank, 4=VESA powerdown when supported
for fb in /sys/class/graphics/fb*/blank; do
  [[ -e "${fb}" ]] || continue
  echo 1 >"${fb}" 2>/dev/null || true
done

if [[ "${off}" -eq 0 ]]; then
  log "no eDP/LVDS backlight/dpms nodes found — nothing to power off"
  exit 0
fi
log "physical panel off (machine stays awake)"
