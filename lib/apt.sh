# shellcheck shell=bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source, do not run.">&2; exit 1; }

################################################################################
apt_requirements_check() {
  # Require APT tools
  if ! command -v apt-get >/dev/null || ! command -v dpkg >/dev/null; then
    fatal "This script only supports APT-based Linux distributions (Debian/Ubuntu/etc.)."
  fi

  # Require 'sudo'
  if ! command -v sudo >/dev/null; then
    error "'sudo' is required but not installed."
    fatal "Install it with: su -c 'apt-get update && apt-get install -y sudo'"
  fi

  SYS_ARCH="$(dpkg --print-architecture)"
  readonly SYS_ARCH
}

################################################################################
require_packages_apt() {
  local missing=()

  # Collect missing packages
  for pkg in "$@"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
      missing+=("$pkg")
    fi
  done

  # All present → nothing to do
  [[ ${#missing[@]} -eq 0 ]] && return 0

  info "Installing required packages..."
  sudo apt-get update -qq
  sudo apt-get install -y "${missing[@]}"
}