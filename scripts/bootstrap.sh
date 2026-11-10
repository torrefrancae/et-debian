#!/usr/bin/env bash
# et-debian: one-shot native Debian lab bootstrap. NO Docker.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${HERE}/lib.sh"

export ET_HOSTNAME="${ET_HOSTNAME:-et-debian}"
export ET_TIMEZONE="${ET_TIMEZONE:-Asia/Manila}"
export CREATE_ETSHARE="${CREATE_ETSHARE:-1}"
export CREATE_ET_DEV="${CREATE_ET_DEV:-1}"
export CREATE_ET_STARTUP="${CREATE_ET_STARTUP:-1}"

log "bootstrap start (repo=${REPO_ROOT})"
ensure_no_docker

chmod +x "${HERE}"/*.sh "${REPO_ROOT}/tools/"*.sh "${REPO_ROOT}/tools/"*.py 2>/dev/null || true

bash "${HERE}/10-base.sh"
bash "${HERE}/20-users.sh"
bash "${HERE}/30-desktop.sh"
bash "${HERE}/40-apps.sh"
bash "${HERE}/50-tools.sh"
bash "${HERE}/60-power.sh"

log "bootstrap complete — no containers installed"
log "next: clone private product trees into ~/proj/dev (not this public repo)"
