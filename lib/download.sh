# shellcheck shell=bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source, do not run." >&2; exit 1; }

download() {
  local url="$1"
  local dest="$2"
  local user="$3"

  [[ -z "$dest" ]] && dest="${MC_INSTANCES}/${MC_NAME}"
  [[ -z "$user" ]] && user="${MC_USER}"
  [[ -d "$dest" ]] || fatal "Destination directory '$dest' does not exist."
  id -u "$user" >/dev/null 2>&1 || fatal "User '$user' not found."

  require_packages_apt curl jq ca-certificates

  info "Destination: $dest, User: $user"

  local latest_ver expected_sha1
  if [[ -n "$url" ]]; then
    info "--url provided; using custom download."
    latest_ver="custom"
    expected_sha1="SKIP"
  else
    info "Fetching latest vanilla metadata …"
    read -r latest_ver url expected_sha1 <<<"$(get_latest_server_meta)" || fatal "Failed to retrieve metadata."
  fi

  info "Resolved metadata: version=${latest_ver}, url=${url}, sha1=${expected_sha1}"

  [[ -n "${url:-}" && "${url:-}" != "null" ]] || fatal "Empty download URL from metadata."
  [[ "$url" =~ ^https?:// ]] || fatal "Bad download URL: $url"

  local jar_name jar_path
  if [[ "$latest_ver" == "custom" ]]; then
    jar_name="$(basename "$url")"
  else
    jar_name="minecraft_server_${latest_ver}.jar"
  fi
  jar_path="${dest}/${jar_name}"

  verify_checksum() {
    local actual
    actual=$(sha1sum "$1" | awk '{print $1}')
    [[ "$2" == "$actual" ]]
  }

  if [[ -f "$jar_path" ]]; then
    info "JAR already exists; validating …"
    if [[ "$expected_sha1" == "SKIP" ]] || verify_checksum "$jar_path" "$expected_sha1"; then
      info "Existing file is valid – nothing to do."
      return 0
    else
      warn "Checksum mismatch – re-downloading."
      sudo -u "$user" rm -f "$jar_path"
    fi
  fi

  info "Downloading $(basename "$jar_path") from: $url"
  # Drop -s so if it fails we see why; add retries and a timeout.
  if ! sudo -u "$user" curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$jar_path" "$url"; then
    warn "curl error while fetching: $url"
    fatal "Download failed from $url"
  fi

  if [[ "$expected_sha1" != "SKIP" ]]; then
    info "Verifying checksum …"
    verify_checksum "$jar_path" "$expected_sha1" || fatal "SHA-1 mismatch after download."
    info "Checksum OK."
  else
    info "Checksum skipped (no SHA-1 available)."
  fi

  info "Download complete: $jar_path"
}
