#!/usr/bin/env bash
# Ensure only the installer user `et` (plus root). Extra lab users are opt-in.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ensure_user() {
  local name="$1"
  local comment="${2:-}"
  if id "${name}" >/dev/null 2>&1; then
    log "user ${name} exists"
    return
  fi
  log "create user ${name}"
  as_root adduser --disabled-password --gecos "${comment}" "${name}"
  as_root passwd -d "${name}" || true
  log "set a password for ${name} with: sudo passwd ${name}"
}

# et should already exist from the installer
if ! id et >/dev/null 2>&1; then
  die "user et missing — create during Debian install"
fi

# Prefer sudo for et when possible (operator may already have done this)
if ! groups et | grep -qw sudo; then
  log "add et to sudo (if allowed)"
  as_root usermod -aG sudo et || log "could not add et to sudo — use su with root password"
fi

# Default OFF — host keeps only et + root unless explicitly enabled.
if [[ "${CREATE_ETSHARE:-0}" == "1" ]]; then
  ensure_user etshare "shared lab account"
fi
if [[ "${CREATE_ET_DEV:-0}" == "1" ]]; then
  ensure_user et-dev "dev account"
fi
if [[ "${CREATE_ET_STARTUP:-0}" == "1" ]]; then
  ensure_user et-startup "startup / kiosk account"
fi

log "users done (default: et + root only)"
