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

get_latest_server_meta() {
  local manifest_url="$MC_VERSION_MANIFEST_URL"
  local latest_ver
  local meta_url

  latest_ver=$(curl -s "$manifest_url" | jq -r '.latest.release')
  meta_url=$(curl -s "$manifest_url" | \
             jq -r --arg ver "$latest_ver" '.versions[] | select(.id == $ver) | .url')

  if [[ -z "$meta_url" ]]; then
    echo "Error: could not resolve metadata URL for $latest_ver" >&2
    return 1
  fi

  local server_url sha1
  read -r server_url sha1 <<<"$(curl -s "$meta_url" | \
        jq -r '.downloads.server | "\(.url) \(.sha1)"')"

  [[ -n "$server_url" && -n "$sha1" ]] || {
    echo "Error: incomplete server metadata" >&2
    return 1
  }

  echo "$latest_ver $server_url $sha1"
}
