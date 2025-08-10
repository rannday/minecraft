# shellcheck shell=bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source, do not run.">&2; exit 1; }

################################################################################
resolve_symlink() {
  local target="$1"

  # Start in a subshell to avoid changing the caller's PWD
  (
    cd "$(dirname "$target")" || exit 1
    target="$(basename "$target")"

    # Follow symlinks until real file is found
    while [ -L "$target" ]; do
      target="$(readlink "$target")"
      # If it's an absolute symlink, cd to its dir
      cd "$(dirname "$target")" || exit 1
      target="$(basename "$target")"
    done

    # Print the resolved absolute path
    echo "$(pwd -P)/$target"
  )
}

################################################################################
# Fetch and cache the Mojang version manifest
cache_manifest() {
  command -v curl >/dev/null || fatal "'curl' is required but not installed."

  local cache_dir="$BASE_DIR/.cache"
  local manifest_file="$cache_dir/version_manifest.json"

  mkdir -p "$cache_dir"

  # Download only if modified since last cached version
  if curl -fsSL -z "$manifest_file" -o "$manifest_file" "$MC_VERSION_MANIFEST_URL"; then
    info "Manifest cached at $manifest_file" >&2
  else
    warn "Failed to update manifest; using cached version if available."
  fi

  [[ -f "$manifest_file" ]] || fatal "Manifest not available and could not be downloaded."
  echo "$manifest_file"
}

################################################################################
# Return the latest Minecraft server version, download URL, and SHA1 checksum
get_latest_server_meta() {
  command -v jq >/dev/null || fatal "'jq' is required but not installed."

  local manifest_file
  manifest_file=$(cache_manifest)

  local latest_ver meta_url server_info server_url sha1
  latest_ver=$(jq -r '.latest.release' <"$manifest_file")
  meta_url=$(jq -r --arg ver "$latest_ver" '.versions[] | select(.id == $ver) | .url' <"$manifest_file")

  [[ -n "$meta_url" ]] || fatal "Could not resolve metadata URL for $latest_ver"
  info "Latest=$latest_ver"
  info "Meta URL=$meta_url"

  if ! server_info=$(curl -fsSL --connect-timeout 15 --max-time 60 --retry 3 --retry-delay 1 --retry-connrefused \
        -H 'Accept: application/json' "$meta_url"); then
    fatal "Failed to fetch metadata for version $latest_ver"
  fi

  info "Metadata bytes=${#server_info}"

  local dl_keys
  dl_keys=$(jq -r '.downloads | keys | join(",")' <<<"$server_info" 2>/dev/null || echo "")
  info "Downloads keys=${dl_keys:-none}"

  read -r server_url sha1 <<<"$(
    jq -r '[.downloads.server.url // empty, .downloads.server.sha1 // empty] | @tsv' <<<"$server_info"
  )"

  if [[ -z "$server_url" || -z "$sha1" ]]; then
    local head
    head=$(printf '%s' "$server_info" | head -c 200 | tr '\n' ' ')
    warn "Server URL or SHA1 missing; head=${head}"
    fatal "Incomplete server metadata for version $latest_ver"
  fi

  info "Server URL resolved"
  printf '%s\n%s\n%s\n' "$latest_ver" "$server_url" "$sha1"
}
