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
