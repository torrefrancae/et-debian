#!/usr/bin/env bash
# Browser + Cursor — downloaded at install time. No Docker.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ARCH="$(dpkg --print-architecture)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

install_chrome() {
  if command -v google-chrome >/dev/null 2>&1 || command -v google-chrome-stable >/dev/null 2>&1; then
    log "Chrome already installed"
    return
  fi
  case "${ARCH}" in
    amd64)
      log "install Google Chrome (amd64 .deb)"
      curl -fsSL -o "${TMP}/chrome.deb" \
        "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
      as_root apt-get install -y "${TMP}/chrome.deb" || apt_install "${TMP}/chrome.deb"
      ;;
    arm64)
      log "Chrome: official linux arm64 channel — trying .deb if available"
      # Google may publish arm64; fallback to Chromium from Debian.
      if curl -fsSL -o "${TMP}/chrome.deb" \
        "https://dl.google.com/linux/direct/google-chrome-stable_current_arm64.deb"; then
        as_root apt-get install -y "${TMP}/chrome.deb" || apt_install chromium
      else
        log "Chrome arm64 .deb unavailable — install chromium"
        apt_install chromium
      fi
      ;;
    *)
      log "unsupported arch ${ARCH} for Chrome — install chromium"
      apt_install chromium
      ;;
  esac
}

install_cursor() {
  if command -v cursor >/dev/null 2>&1 || [[ -x /usr/bin/cursor ]]; then
    log "Cursor already installed"
    return
  fi
  log "install Cursor (aptrepo or .deb)"
  # Prefer official apt repo when keyrings are available.
  if [[ ! -f /etc/apt/sources.list.d/cursor.list ]]; then
    as_root bash -c '
      set -e
      install -d /etc/apt/keyrings
      curl -fsSL https://downloads.cursor.com/keys/anysphere.asc \
        | gpg --dearmor -o /etc/apt/keyrings/cursor.gpg
      echo "deb [arch=amd64,arm64 signed-by=/etc/apt/keyrings/cursor.gpg] https://downloads.cursor.com/aptrepo stable main" \
        > /etc/apt/sources.list.d/cursor.list
    ' || true
    apt_update || true
  fi
  if as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y cursor; then
    return
  fi
  # Fallback: golden .deb (not AppImage)
  local url
  case "${ARCH}" in
    amd64) url="https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/latest" ;;
    arm64) url="https://api2.cursor.sh/updates/download/golden/linux-arm64-deb/cursor/latest" ;;
    *) log "no Cursor build for ${ARCH}"; return 0 ;;
  esac
  if ! curl -fsSL -L -o "${TMP}/cursor.deb" "${url}"; then
    log "Cursor download failed — https://cursor.com/download"
    return 0
  fi
  as_root apt-get install -y "${TMP}/cursor.deb" || \
    log "Cursor .deb install failed — https://cursor.com/download"
}

install_chrome
install_cursor

log "apps done (Screenshot Monitor / proprietary extras are optional — see docs/)"
