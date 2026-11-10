#!/usr/bin/env bash
# Lab apps — native .deb/apt only. No Docker.
# Codifies: Chrome, Cursor, Screenshot Monitor, AnyDesk, Remmina, helpers.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ARCH="$(dpkg --print-architecture)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

BOOKWORM_GTK_SHARP_BASE="https://deb.debian.org/debian/pool/main/g/gtk-sharp2"
SSM_DEB_URL="${SSM_DEB_URL:-https://screenshotmonitor-download.s3.amazonaws.com/linux/ScreenshotMonitor.deb}"
# Pin a known-good AnyDesk amd64 build (site “latest” links are flaky / CF-gated).
ANYDESK_AMD64_URL="${ANYDESK_AMD64_URL:-https://download.anydesk.com/linux/anydesk_6.4.0-1_amd64.deb}"

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
      as_root apt-get install -y "${TMP}/chrome.deb"
      ;;
    arm64)
      log "Chrome arm64 .deb or chromium fallback"
      if curl -fsSL -o "${TMP}/chrome.deb" \
        "https://dl.google.com/linux/direct/google-chrome-stable_current_arm64.deb"; then
        as_root apt-get install -y "${TMP}/chrome.deb" || apt_install chromium
      else
        apt_install chromium
      fi
      ;;
    *)
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
  local url
  case "${ARCH}" in
    amd64) url="https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/latest" ;;
    arm64) url="https://api2.cursor.sh/updates/download/golden/linux-arm64-deb/cursor/latest" ;;
    *) log "no Cursor build for ${ARCH}"; return 0 ;;
  esac
  curl -fsSL -L -o "${TMP}/cursor.deb" "${url}" || {
    log "Cursor download failed — https://cursor.com/download"
    return 0
  }
  as_root apt-get install -y "${TMP}/cursor.deb" || \
    log "Cursor .deb install failed — https://cursor.com/download"
}

install_gtk_sharp2() {
  if dpkg -s gtk-sharp2 >/dev/null 2>&1; then
    log "gtk-sharp2 already installed"
    return
  fi
  # Trixie dropped gtk-sharp2; pull Bookworm runtime debs for this arch.
  log "install gtk-sharp2 from Debian bookworm pool (${ARCH})"
  local dir="${TMP}/gtk-sharp2"
  mkdir -p "${dir}"
  local files=(
    "libglib2.0-cil_2.12.40-3.1_${ARCH}.deb"
    "libgtk2.0-cil_2.12.40-3.1_${ARCH}.deb"
    "libglade2.0-cil_2.12.40-3.1_${ARCH}.deb"
    "gtk-sharp2_2.12.40-3.1_all.deb"
  )
  local f
  for f in "${files[@]}"; do
    curl -fsSL -o "${dir}/${f}" "${BOOKWORM_GTK_SHARP_BASE}/${f}" || \
      die "failed to download ${f}"
  done
  # Native GTK2 bits still in trixie (t64 names).
  apt_install libgtk2.0-0t64 || apt_install libgtk2.0-0 || true
  # libglade2 may be gone; try bookworm if missing.
  if ! dpkg -s libglade2-0 >/dev/null 2>&1 && ! dpkg -s libglade2-0t64 >/dev/null 2>&1; then
    log "fetch bookworm libglade2-0"
    local glade
    glade="$(curl -fsSL "https://packages.debian.org/bookworm/${ARCH}/libglade2-0/download" \
      | grep -oE 'https?://(deb|ftp)\.debian\.org/debian/pool/[^\"[:space:]]+\.deb' | head -1 || true)"
    if [[ -n "${glade}" ]]; then
      curl -fsSL -o "${dir}/libglade2-0.deb" "${glade}"
      as_root dpkg -i "${dir}/libglade2-0.deb" || as_root apt-get install -y -f || true
    fi
  fi
  as_root dpkg -i "${dir}"/*.deb || as_root apt-get install -y -f
  # If meta still missing (Provides conflict), synthesize with equivs.
  if ! dpkg -s gtk-sharp2 >/dev/null 2>&1; then
    log "gtk-sharp2 meta missing — create equivs package"
    apt_install equivs
    cat > "${TMP}/gtk-sharp2-equiv" <<'EOF'
Section: misc
Priority: optional
Standards-Version: 3.9.2
Package: gtk-sharp2
Version: 2.12.40-3.1+etdebian
Maintainer: et-debian bootstrap
Depends: libgtk2.0-cil, libglib2.0-cil, libglade2.0-cil
Description: equivs meta for Screenshot Monitor on Debian 13
EOF
    (cd "${TMP}" && equivs-build gtk-sharp2-equiv >/dev/null)
    as_root dpkg -i "${TMP}"/gtk-sharp2_*.deb
  fi
}

install_screenshot_monitor() {
  if dpkg -s screenshotmonitor >/dev/null 2>&1 || command -v screenshotmonitor >/dev/null 2>&1; then
    log "Screenshot Monitor already installed"
  else
    log "install Screenshot Monitor 1.3.1"
    apt_install mono-complete xprintidle xdotool gnome-screenshot
    install_gtk_sharp2
    curl -fsSL -o "${TMP}/ScreenshotMonitor.deb" "${SSM_DEB_URL}"
    as_root apt-get install -y "${TMP}/ScreenshotMonitor.deb" || \
      as_root dpkg -i "${TMP}/ScreenshotMonitor.deb" || \
      as_root apt-get install -y -f
  fi

  # Autostart for et (sole lab account)
  local desk_src home
  desk_src="/usr/share/applications/screenshotmonitor.desktop"
  if [[ ! -f "${desk_src}" ]]; then
    desk_src="$(find /usr/share/applications -iname '*screenshot*monitor*.desktop' 2>/dev/null | head -1 || true)"
  fi
  if [[ -n "${desk_src}" && -f "${desk_src}" ]] && id et >/dev/null 2>&1; then
    home="$(getent passwd et | cut -d: -f6)"
    as_root install -d -o et -g et "${home}/.config/autostart"
    as_root install -m 0644 -o et -g et "${desk_src}" \
      "${home}/.config/autostart/screenshotmonitor.desktop"
    log "Screenshot Monitor autostart → et"
  fi
}

install_bookworm_deb() {
  # $1 = bookworm package name; downloads matching arch .deb into $TMP and dpkg -i
  local pkg="$1"
  local url
  url="$(curl -fsSL "https://packages.debian.org/bookworm/${ARCH}/${pkg}/download" \
    | grep -oE 'https?://(deb|ftp)\.debian\.org/debian/pool/[^\"[:space:]]+\.deb' | head -1 || true)"
  if [[ -z "${url}" ]]; then
    log "bookworm ${pkg}: no download URL"
    return 1
  fi
  curl -fsSL -o "${TMP}/${pkg}.deb" "${url}"
  as_root dpkg -i "${TMP}/${pkg}.deb" || as_root apt-get install -y -f || true
}

install_anydesk() {
  if command -v anydesk >/dev/null 2>&1; then
    log "AnyDesk already installed"
    return
  fi
  case "${ARCH}" in
    amd64)
      log "install AnyDesk (${ANYDESK_AMD64_URL})"
      # Trixie dropped libgtkglext1 — pull from bookworm first.
      if ! dpkg -s libgtkglext1 >/dev/null 2>&1; then
        install_bookworm_deb libgtkglext1 || true
      fi
      curl -fsSL -o "${TMP}/anydesk.deb" "${ANYDESK_AMD64_URL}" || {
        log "AnyDesk download failed — install manually from https://anydesk.com/downloads"
        return 0
      }
      if ! as_root apt-get install -y "${TMP}/anydesk.deb"; then
        as_root dpkg -i "${TMP}/anydesk.deb" || true
        as_root apt-get install -y -f || true
      fi
      if command -v anydesk >/dev/null 2>&1; then
        as_root systemctl enable --now anydesk || true
      else
        log "AnyDesk install incomplete — check libgtkglext1 / dpkg -l anydesk"
      fi
      ;;
    *)
      log "AnyDesk: no pinned .deb for ${ARCH} — skip (set ANYDESK_AMD64_URL to override)"
      ;;
  esac
}

install_remote_helpers() {
  log "install Remmina + VNC viewer helpers"
  apt_install remmina remmina-plugin-rdp remmina-plugin-vnc tigervnc-viewer || \
    apt_install remmina || true
}

install_chrome
install_cursor
install_screenshot_monitor
install_anydesk
install_remote_helpers

log "apps done (Chrome, Cursor, Screenshot Monitor, AnyDesk, Remmina)"
