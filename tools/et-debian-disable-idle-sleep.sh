#!/usr/bin/env bash
# Disable idle / lid auto-suspend. Scheduled 06:00 sleep (rtcwake) stays allowed.
# No Docker. Safe to re-run.
set -euo pipefail

log() { logger -t et-debian-power "$*"; printf '[et-debian-power] %s\n' "$*"; }

if [[ "${EUID}" -ne 0 ]]; then
  log "must run as root"
  exit 1
fi

# 1) systemd-logind: never idle-sleep or lid-sleep. Manual/scheduled suspend OK.
install -d /etc/systemd/logind.conf.d
cat >/etc/systemd/logind.conf.d/et-debian-no-idle-sleep.conf <<'EOF'
[Login]
# Stay awake unless the 06:00 et-debian-sleep.timer / rtcwake path runs.
IdleAction=ignore
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
# Keep Suspend key / rtcwake able to suspend:
HandleSuspendKey=suspend
HandleHibernateKey=ignore
EOF
systemctl restart systemd-logind || true
log "logind: IdleAction=ignore, lid suspend ignored"

# 2) Do NOT mask suspend.target — rtcwake / scheduled sleep needs it.
# Idle GNOME suspend is disabled below instead.

# 3) System-wide GNOME: never auto-suspend on idle (AC or battery)
install -d /etc/dconf/db/local.d /etc/dconf/profile
if [[ ! -f /etc/dconf/profile/user ]]; then
  cat >/etc/dconf/profile/user <<'EOF'
user-db:user
system-db:local
EOF
fi
cat >/etc/dconf/db/local.d/00-et-debian-power <<'EOF'
[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
sleep-inactive-ac-timeout=0
sleep-inactive-battery-timeout=0
power-button-action='nothing'
idle-dim=false

[org/gnome/desktop/session]
idle-delay=uint32 0

[org/gnome/desktop/screensaver]
idle-activation-enabled=false
lock-enabled=false
EOF
if command -v dconf >/dev/null 2>&1; then
  dconf update || true
  log "dconf local DB updated (GNOME idle suspend off)"
else
  log "dconf not installed — per-user gsettings still applied"
fi

# 4) Per-user gsettings for existing sessions / homes
for u in et; do
  if ! id "${u}" >/dev/null 2>&1; then
    continue
  fi
  uid="$(id -u "${u}")"
  bus="/run/user/${uid}/bus"
  run_gs() {
    if [[ -S "${bus}" ]]; then
      sudo -u "${u}" DBUS_SESSION_BUS_ADDRESS="unix:path=${bus}" gsettings "$@" || true
    else
      # Write directly into dconf user DB when no session bus
      sudo -u "${u}" dbus-run-session -- gsettings "$@" 2>/dev/null || true
    fi
  }
  if command -v gsettings >/dev/null 2>&1; then
    run_gs set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type nothing
    run_gs set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type nothing
    run_gs set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0
    run_gs set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0
    run_gs set org.gnome.desktop.session idle-delay 0
    run_gs set org.gnome.desktop.screensaver idle-activation-enabled false
    log "gsettings applied for ${u}"
  fi
  # Drop a marker so operators know policy is intentional
  printf 'idle auto-suspend disabled; scheduled sleep via et-debian-sleep.timer\n' \
    >"${home}/.et-debian-power-policy" 2>/dev/null || true
  chown "${u}:${u}" "${home}/.et-debian-power-policy" 2>/dev/null || true
done

log "idle sleep disabled — only et-debian-sleep.timer (06:00 → wake 15:00) should suspend"
