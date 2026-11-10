#!/usr/bin/env bash
# Base OS packages, timezone, ssh, avahi — native apt only.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ensure_no_docker
log "base packages"
apt_update
apt_install \
  ca-certificates curl wget git rsync openssh-server openssh-client \
  avahi-daemon libnss-mdns \
  build-essential pkg-config \
  python3 python3-gi python3-gi-cairo python3-xlib gir1.2-gtk-3.0 \
  xdotool wmctrl \
  htop tmux vim nano unzip zip jq \
  fonts-liberation

TZ="${ET_TIMEZONE:-Asia/Manila}"
log "timezone -> ${TZ}"
as_root timedatectl set-timezone "${TZ}" || true

log "enable ssh + avahi"
as_root systemctl enable --now ssh || as_root systemctl enable --now sshd || true
as_root systemctl enable --now avahi-daemon || true

HOSTN="${ET_HOSTNAME:-et-debian}"
if [[ "$(hostname)" != "${HOSTN}" ]]; then
  log "hostname -> ${HOSTN} (optional; set ET_HOSTNAME to skip)"
  as_root hostnamectl set-hostname "${HOSTN}" || true
fi

mkdir -p "${HOME}/proj" "${HOME}/.local/bin"
log "base done"
