#!/usr/bin/env bash
set -euo pipefail
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
  echo "This script is meant to be sourced, not executed."
  exit 1
}

resolve_symlink() {
  local target=$1
  cd "$(dirname "$target")" || return 1
  target=$(basename "$target")

  # Follow symlinks until we reach the real file
  while [ -L "$target" ]; do
    target=$(readlink "$target")
    cd "$(dirname "$target")" || return 1
    target=$(basename "$target")
  done

  # Get the absolute path
  echo "$(pwd -P)/$target"
}

require_packages() {
  local missing=()

  for pkg in "$@"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
      missing+=("$pkg")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "[apt] All required packages already installed: $*"
    return 0
  fi

  echo "[apt] Missing packages: ${missing[*]}"
  echo "[apt] Running apt update..."
  sudo apt update

  echo "[apt] Installing: ${missing[*]}"
  sudo apt install -y "${missing[@]}"
}

