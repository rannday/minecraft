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
  command -v jq >/dev/null   || fatal "'jq' is required but not installed."

  local manifest_file
  manifest_file=$(cache_manifest)

  local latest_ver meta_url server_info server_url sha1
  latest_ver=$(jq -r '.latest.release' <"$manifest_file")
  meta_url=$(jq -r --arg ver "$latest_ver" '.versions[] | select(.id == $ver) | .url' <"$manifest_file")

  [[ -n "$meta_url" ]] || fatal "Could not resolve metadata URL for $latest_ver"

  # Fetch version-specific metadata
  if ! server_info=$(curl -fsSL --connect-timeout 5 "$meta_url"); then
    fatal "Failed to fetch metadata for version $latest_ver"
  fi

  read -r server_url sha1 <<<"$(jq -r '.downloads.server | "\(.url) \(.sha1)"' <<<"$server_info")"
  [[ -n "$server_url" && -n "$sha1" ]] || fatal "Incomplete server metadata for version $latest_ver"

  printf '%s\n%s\n%s\n' "$latest_ver" "$server_url" "$sha1"
}