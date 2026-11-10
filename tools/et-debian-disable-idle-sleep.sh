#!/usr/bin/env bash
# Screen may blank; machine must NOT idle-suspend.
# Only et-debian-sleep.timer (06:00 → rtcwake 15:00) should suspend.
# No Docker. Safe to re-run.
set -euo pipefail

# Seconds until the display blanks (0 = never). Suspend stays disabled either way.
BLANK_SECS="${ET_DEBIAN_SCREEN_BLANK_SECS:-300}"

log() { logger -t et-debian-power "$*"; printf '[et-debian-power] %s\n' "$*"; }

if [[ "${EUID}" -ne 0 ]]; then
  log "must run as root"
  exit 1
fi

# 1) systemd-logind: never idle-sleep or lid-sleep. Scheduled/manual suspend OK.
install -d /etc/systemd/logind.conf.d
cat >/etc/systemd/logind.conf.d/et-debian-no-idle-sleep.conf <<'EOF'
[Login]
# Stay awake unless the 06:00 et-debian-sleep.timer / rtcwake path runs.
IdleAction=ignore
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
HandleSuspendKey=suspend
HandleHibernateKey=ignore
EOF
systemctl restart systemd-logind || true
log "logind: IdleAction=ignore (no idle suspend); lid ignored"

# 2) Do NOT mask suspend.target — rtcwake needs it for the 06:00 schedule.

# 3) GNOME: blank screen OK; never auto-suspend on AC/battery idle
install -d /etc/dconf/db/local.d /etc/dconf/profile
if [[ ! -f /etc/dconf/profile/user ]]; then
  cat >/etc/dconf/profile/user <<'EOF'
user-db:user
system-db:local
EOF
fi
cat >/etc/dconf/db/local.d/00-et-debian-power <<EOF
[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
sleep-inactive-ac-timeout=0
sleep-inactive-battery-timeout=0
power-button-action='nothing'
idle-dim=true

[org/gnome/desktop/session]
idle-delay=uint32 ${BLANK_SECS}

[org/gnome/desktop/screensaver]
idle-activation-enabled=true
lock-enabled=false
EOF
if command -v dconf >/dev/null 2>&1; then
  dconf update || true
  log "dconf: screen blank ${BLANK_SECS}s; suspend type=nothing"
else
  log "dconf not installed — per-user gsettings still applied"
fi

# 4) Per-user gsettings for et
for u in et; do
  if ! id "${u}" >/dev/null 2>&1; then
    continue
  fi
  uid="$(id -u "${u}")"
  home="$(getent passwd "${u}" | cut -d: -f6)"
  bus="/run/user/${uid}/bus"
  run_gs() {
    if [[ -S "${bus}" ]]; then
      sudo -u "${u}" DBUS_SESSION_BUS_ADDRESS="unix:path=${bus}" gsettings "$@" || true
    else
      sudo -u "${u}" dbus-run-session -- gsettings "$@" 2>/dev/null || true
    fi
  }
  if command -v gsettings >/dev/null 2>&1; then
    run_gs set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type nothing
    run_gs set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type nothing
    run_gs set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0
    run_gs set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0
    run_gs set org.gnome.settings-daemon.plugins.power idle-dim true
    run_gs set org.gnome.desktop.session idle-delay "${BLANK_SECS}"
    run_gs set org.gnome.desktop.screensaver idle-activation-enabled true
    run_gs set org.gnome.desktop.screensaver lock-enabled false
    log "gsettings applied for ${u} (blank ${BLANK_SECS}s, no idle suspend)"
  fi
  printf 'screen may blank; machine stays awake except et-debian-sleep.timer (06:00→15:00)\n' \
    >"${home}/.et-debian-power-policy" 2>/dev/null || true
  chown "${u}:${u}" "${home}/.et-debian-power-policy" 2>/dev/null || true
done

log "policy: display blank OK; CPU awake until scheduled 06:00 suspend / 15:00 wake"
