#!/usr/bin/env bash
# System-wide idle watcher (runs as root via systemd).
# Picks the best local X display (GDM greeter or user session, including xrdp)
# and turns the physical panel off after 5 minutes idle / on again on activity.
# Never suspends — only et-debian-sleep.timer does that at 06:00.
set -euo pipefail

BLANK_SECS="${ET_DEBIAN_SCREEN_BLANK_SECS:-300}"
BLANK_MS=$((BLANK_SECS * 1000))
POLL="${ET_DEBIAN_IDLE_POLL_SECS:-5}"
PANEL_OFF=/usr/local/sbin/et-debian-panel-off
PANEL_ON=/usr/local/sbin/et-debian-panel-on
off=0

log() { logger -t et-debian-display "$*"; printf '[et-debian-display] %s\n' "$*"; }

pick_x() {
  # Prefer an active user graphical session; fall back to GDM greeter on :0.
  local line sid name type remote display seat state user home auth
  local best_disp="" best_auth="" greeter_disp="" greeter_auth=""

  while IFS= read -r line; do
    sid="${line%% *}"
    [[ -n "$sid" ]] || continue
    name="$(loginctl show-session "$sid" -p Name --value 2>/dev/null || true)"
    type="$(loginctl show-session "$sid" -p Type --value 2>/dev/null || true)"
    remote="$(loginctl show-session "$sid" -p Remote --value 2>/dev/null || true)"
    display="$(loginctl show-session "$sid" -p Display --value 2>/dev/null || true)"
    seat="$(loginctl show-session "$sid" -p Seat --value 2>/dev/null || true)"
    state="$(loginctl show-session "$sid" -p State --value 2>/dev/null || true)"
    [[ "$type" == "x11" && -n "$display" ]] || continue

    if [[ "$name" == "Debian-gdm" || "$name" == "gdm" ]]; then
      greeter_disp="$display"
      greeter_auth="/run/user/$(id -u Debian-gdm 2>/dev/null || echo 112)/gdm/Xauthority"
      [[ -e "$greeter_auth" ]] || greeter_auth="/run/user/112/gdm/Xauthority"
      continue
    fi

    user="$name"
    home="$(getent passwd "$user" | cut -d: -f6 || true)"
    auth="${home}/.Xauthority"
    [[ -e "$auth" ]] || continue

    # Prefer active local seat0; otherwise accept remote (xrdp) sessions.
    if [[ "$state" == "active" && ( "$seat" == "seat0" || "$remote" == "no" ) ]]; then
      printf '%s %s\n' "$display" "$auth"
      return 0
    fi
    if [[ -z "$best_disp" ]]; then
      best_disp="$display"
      best_auth="$auth"
    fi
  done < <(loginctl list-sessions --no-legend 2>/dev/null || true)

  if [[ -n "$best_disp" && -n "$best_auth" ]]; then
    printf '%s %s\n' "$best_disp" "$best_auth"
    return 0
  fi
  if [[ -n "$greeter_disp" && -e "$greeter_auth" ]]; then
    printf '%s %s\n' "$greeter_disp" "$greeter_auth"
    return 0
  fi
  return 1
}

idle_ms() {
  local disp="$1" auth="$2"
  DISPLAY="$disp" XAUTHORITY="$auth" xprintidle 2>/dev/null || echo 0
}

log "system idle panel watcher start (blank=${BLANK_SECS}s)"

while true; do
  if ! read -r disp auth < <(pick_x); then
    sleep "${POLL}"
    continue
  fi
  idle="$(idle_ms "$disp" "$auth")"
  if (( idle >= BLANK_MS )); then
    if [[ "${off}" -eq 0 ]]; then
      "${PANEL_OFF}" >/dev/null 2>&1 || true
      off=1
      log "panel off (idle ${idle}ms on ${disp})"
    fi
  else
    if [[ "${off}" -eq 1 ]]; then
      "${PANEL_ON}" >/dev/null 2>&1 || true
      off=0
      log "panel on (activity ${idle}ms on ${disp})"
    fi
  fi
  sleep "${POLL}"
done
