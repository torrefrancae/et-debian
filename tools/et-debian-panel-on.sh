#!/usr/bin/env bash
# Restore physical panel after et-debian-panel-off.
set -euo pipefail

log() { logger -t et-debian-panel "$*"; printf '[et-debian-panel] %s\n' "$*"; }

if [[ "${EUID}" -ne 0 ]]; then
  log "must run as root"
  exit 1
fi

mkdir -p /var/lib/et-debian
# Pause keep-off timer re-assert until an explicit panel-off
touch /var/lib/et-debian/panel-keep-on

for dpms in /sys/class/drm/card*-eDP-*/dpms /sys/class/drm/card*-LVDS-*/dpms; do
  [[ -e "${dpms}" ]] || continue
  printf 'on\n' | tee "${dpms}" >/dev/null 2>/dev/null || \
    printf 'On\n' | tee "${dpms}" >/dev/null 2>/dev/null || true
  log "DRM dpms on: ${dpms} -> $(cat "${dpms}" 2>/dev/null || echo '?')"
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
  bpf="${dir}/bl_power"
  max="$(cat "${maxf}" 2>/dev/null || echo 100)"
  val="${max}"
  if [[ -f "${saved}" ]]; then
    val="$(cat "${saved}")"
  else
    # ~60% of max if we never saved
    val=$(( max * 60 / 100 ))
    [[ "${val}" -gt 0 ]] || val=1
  fi
  if [[ -e "${bpf}" ]]; then
    echo 0 >"${bpf}" 2>/dev/null || true
  fi
  echo "${val}" >"${bl}" 2>/dev/null || true
  log "backlight restore: ${bl} -> ${val}"
done

# Wake local GDM/X if it was left in "Monitor is Off" (black + cursor).
if [[ -S /tmp/.X11-unix/X0 ]]; then
  for xa in /run/user/*/gdm/Xauthority /run/user/112/gdm/Xauthority; do
    [[ -e "${xa}" ]] || continue
    DISPLAY=:0 XAUTHORITY="${xa}" xset dpms force on 2>/dev/null || true
    DISPLAY=:0 XAUTHORITY="${xa}" xset -dpms 2>/dev/null || true
  done
fi

log "physical panel on (keep-off paused until et-debian-panel-off)"
