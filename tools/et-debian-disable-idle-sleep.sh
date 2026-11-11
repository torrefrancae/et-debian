#!/usr/bin/env bash
# Machine must NOT idle-suspend. Only et-debian-sleep.timer (06:00) suspends.
# Display: no fake black blank (blinking cursor). Real panel off via DRM/backlight.
# No Docker. Safe to re-run.
set -euo pipefail

BLANK_SECS="${ET_DEBIAN_SCREEN_BLANK_SECS:-300}"

log() { logger -t et-debian-power "$*"; printf '[et-debian-power] %s\n' "$*"; }

if [[ "${EUID}" -ne 0 ]]; then
  log "must run as root"
  exit 1
fi

# 1) systemd-logind: never idle/lid/key suspend — only rtcwake schedule may sleep
install -d /etc/systemd/logind.conf.d
cat >/etc/systemd/logind.conf.d/et-debian-no-idle-sleep.conf <<'EOF'
[Login]
IdleAction=ignore
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleSuspendKeyLongPress=ignore
AllowSuspend=no
AllowHibernation=no
AllowHybridSleep=no
AllowSuspendThenHibernate=no
EOF
systemctl restart systemd-logind || true
log "logind: no idle/lid/key suspend (AllowSuspend=no)"

# 2) GNOME: disable fake screensaver blank (black + cursor). Panel-off helper handles display.
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
fi

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
    run_gs set org.gnome.settings-daemon.plugins.power idle-dim false
    run_gs set org.gnome.desktop.session idle-delay 0
    run_gs set org.gnome.desktop.screensaver idle-activation-enabled false
    run_gs set org.gnome.desktop.screensaver lock-enabled false
  fi
  printf 'no idle suspend; no fake blank; panel off via et-debian-panel-off / idle helper (%ss)\n' \
    "${BLANK_SECS}" >"${home}/.et-debian-power-policy" 2>/dev/null || true
  chown "${u}:${u}" "${home}/.et-debian-power-policy" 2>/dev/null || true
done

# 3) Allow et to toggle physical panel without a password prompt
install -d /etc/sudoers.d
cat >/etc/sudoers.d/et-debian-panel <<'EOF'
et ALL=(root) NOPASSWD: /usr/local/sbin/et-debian-panel-off, /usr/local/sbin/et-debian-panel-on
EOF
chmod 440 /etc/sudoers.d/et-debian-panel
visudo -cf /etc/sudoers.d/et-debian-panel >/dev/null

log "policy: no idle suspend; real panel off via DRM/backlight (blank=${BLANK_SECS}s helper)"
