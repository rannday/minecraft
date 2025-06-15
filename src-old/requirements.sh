#!/usr/bin/env bash
set -euo pipefail
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source, don't run."; return 1; }

# Ensure the flag is always defined to avoid set -u errors in subshells
: "${APT_UPDATED:=0}"

require_packages_apt() {
  local missing=()

  for pkg in "$@"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
      missing+=("$pkg")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    # Quiet success
    return 0
  fi

  echo "[apt] Missing packages: ${missing[*]}"

  # Only run apt update once per session
  if [[ "$APT_UPDATED" -eq 0 ]]; then
    echo "[apt] Updating package lists..."
    sudo apt-get update -qq
    APT_UPDATED=1
  fi

  echo "[apt] Installing: ${missing[*]}"
  sudo apt-get install -y "${missing[@]}"
}

# scripts
require_packages_apt curl sudo jq tmux
# java
require_packages_apt wget gnupg software-properties-common
