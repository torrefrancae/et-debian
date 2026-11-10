#!/usr/bin/env bash
# Restore physical panel after et-debian-panel-off.
set -euo pipefail

log() { logger -t et-debian-panel "$*"; printf '[et-debian-panel] %s\n' "$*"; }

if [[ "${EUID}" -ne 0 ]]; then
  log "must run as root"
  exit 1
fi

for dpms in /sys/class/drm/card*-eDP-*/dpms /sys/class/drm/card*-LVDS-*/dpms; do
  [[ -e "${dpms}" ]] || continue
  echo on >"${dpms}" 2>/dev/null || true
  log "DRM dpms on: ${dpms}"
done

for fb in /sys/class/graphics/fb*/blank; do
  [[ -e "${fb}" ]] || continue
  echo 0 >"${fb}" 2>/dev/null || true
done

for bl in /sys/class/backlight/*/brightness; do
  [[ -e "${bl}" ]] || continue
  dir="$(dirname "${bl}")"
  name="$(basename "${dir}")"
  saved="/var/lib/et-debian/backlight-${name}.saved"
  maxf="${dir}/max_brightness"
  max="$(cat "${maxf}" 2>/dev/null || echo 100)"
  val="${max}"
  if [[ -f "${saved}" ]]; then
    val="$(cat "${saved}")"
  else
    # ~60% of max if we never saved
    val=$(( max * 60 / 100 ))
    [[ "${val}" -gt 0 ]] || val=1
  fi
  echo "${val}" >"${bl}" 2>/dev/null || true
  log "backlight restore: ${bl} -> ${val}"
done

log "physical panel on"
