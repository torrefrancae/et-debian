#!/usr/bin/env bash
# Enable RTC alarm wake from Linux (sysfs + ACPI). No Docker.
# Safe / idempotent. Does not open BIOS — only flips what the kernel exposes.
set -euo pipefail

log() { logger -t et-debian-rtc "$*"; printf '[et-debian-rtc] %s\n' "$*"; }

if [[ "${EUID}" -ne 0 ]]; then
  log "must run as root"
  exit 1
fi

enable_sysfs_wakeup() {
  local path="$1"
  [[ -f "${path}" ]] || return 0
  local cur
  cur="$(cat "${path}" 2>/dev/null || true)"
  if [[ "${cur}" == "enabled" ]]; then
    log "already enabled: ${path}"
    return 0
  fi
  if echo enabled >"${path}" 2>/dev/null; then
    log "enabled: ${path}"
  else
    log "could not write enabled → ${path} (cur=${cur:-?})"
  fi
}

# 1) RTC device wakeup attribute (several layouts across kernels)
for p in \
  /sys/class/rtc/rtc0/power/wakeup \
  /sys/class/rtc/rtc0/device/power/wakeup \
  /sys/devices/virtual/rtc/rtc0/power/wakeup
 do
  enable_sysfs_wakeup "${p}"
done

if [[ -e /sys/class/rtc/rtc0/device ]]; then
  dev="$(readlink -f /sys/class/rtc/rtc0/device || true)"
  if [[ -n "${dev}" && -f "${dev}/power/wakeup" ]]; then
    enable_sysfs_wakeup "${dev}/power/wakeup"
  fi
  parent="$(dirname "${dev}")"
  if [[ -n "${parent}" && -f "${parent}/power/wakeup" ]]; then
    enable_sysfs_wakeup "${parent}/power/wakeup"
  fi
fi

# 2) ACPI wakeup table — enable RTC / ALARM rows that are disabled
if [[ -f /proc/acpi/wakeup ]]; then
  while read -r device rest; do
    [[ "${device}" == "Device" || -z "${device}" ]] && continue
    case "${device}" in
      RTC*|RTCS|ALARM*|PNP0B*)
        if echo "${rest}" | grep -qw disabled; then
          if echo "${device}" >/proc/acpi/wakeup 2>/dev/null; then
            log "ACPI wakeup toggled on: ${device}"
          else
            log "ACPI wakeup toggle failed: ${device}"
          fi
        else
          log "ACPI wakeup already on: ${device}"
        fi
        ;;
    esac
  done </proc/acpi/wakeup
  log "ACPI RTC rows:"
  grep -E 'RTC|ALARM|PNP0B' /proc/acpi/wakeup 2>/dev/null | while read -r line; do
    log "  ${line}"
  done || true
else
  log "no /proc/acpi/wakeup on this kernel"
fi

# 3) Prefer deep (S3) over s2idle when both exist — RTC alarm is more reliable
if [[ -f /sys/power/mem_sleep ]]; then
  avail="$(cat /sys/power/mem_sleep)"
  log "mem_sleep available: ${avail}"
  if grep -qw deep <<<"${avail}"; then
    if echo deep >/sys/power/mem_sleep 2>/dev/null; then
      log "prefer mem_sleep=deep for RTC wake"
    else
      log "could not set mem_sleep=deep (kept: $(cat /sys/power/mem_sleep))"
    fi
  fi
fi

# Persist deep preference across boots (tmpfiles applies early)
if [[ "${ET_DEBIAN_RTC_INSTALL_HOOKS:-1}" == "1" ]]; then
  mkdir -p /etc/tmpfiles.d
  cat >/etc/tmpfiles.d/et-debian-mem-sleep.conf <<'EOF'
# Prefer S3 (deep) so RTC alarm wake works more reliably than s2idle.
w /sys/power/mem_sleep - - - - deep
EOF
fi

log "RTC wake enable pass complete"
