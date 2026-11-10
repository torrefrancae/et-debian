#!/usr/bin/env bash
# Shared helpers for et-debian bootstrap (no Docker).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

log() { printf '[et-debian] %s\n' "$*"; }
die() { printf '[et-debian] ERROR: %s\n' "$*" >&2; exit 1; }

need_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    return 0
  fi
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    exec sudo -E bash "$0" "$@"
  fi
  die "need root (sudo or re-run via: su -c 'bash $0')"
}

as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
    return
  fi
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo -E "$@"
    return
  fi
  # Interactive su; password never stored.
  su -c "$(printf '%q ' "$@")"
}

apt_install() {
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

apt_update() {
  as_root env DEBIAN_FRONTEND=noninteractive apt-get update -y
}

ensure_no_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "WARNING: docker binary present — this bootstrap does not use it and will not install containers."
  fi
}
