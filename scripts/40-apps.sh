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
  if command -v cursor >/dev/null 2>&1 || [[ -x /usr/bin/cursor ]] || [[ -x /opt/Cursor/cursor ]]; then
    log "Cursor already installed"
    return
  fi
  log "install Cursor (.deb via official download API)"
  # Public download endpoint; resolves to latest linux .deb for arch.
  local url
  case "${ARCH}" in
    amd64) url="https://api2.cursor.sh/updates/download/golden/linux-x64/cursor/2.0" ;;
    arm64) url="https://api2.cursor.sh/updates/download/golden/linux-arm64/cursor/2.0" ;;
    *) log "no Cursor build for ${ARCH}"; return 0 ;;
  esac
  if ! curl -fsSL -L -o "${TMP}/cursor.deb" "${url}"; then
    log "Cursor download failed — install manually from https://cursor.com/downloads"
    return 0
  fi
  as_root apt-get install -y "${TMP}/cursor.deb" || {
    log "Cursor .deb install failed — open https://cursor.com/downloads"
  }
}

install_chrome
install_cursor

log "apps done (Screenshot Monitor / proprietary extras are optional — see docs/)"
