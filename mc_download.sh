#!/usr/bin/env bash
set -euo pipefail
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && { echo "Run, do not source." >&2; exit 1; }
BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$BASE_DIR/lib/log.sh"
trap 'warn "Interrupted. Exiting."; exit 1' INT TERM

source "$BASE_DIR/lib/apt_check.sh"
apt_requirements_check

################################################################################
# Download Minecraft
################################################################################

download() {

  print_download_help() {
    cat <<EOF
Usage: $(basename "$0") download [options]

       --url   URL   Custom URL for server JAR
  -d, --dest   DIR   Destination directory (default: $MC_INSTANCES/$MC_NAME)
  -u, --user   USER  Run curl as USER (default: $MC_USER)
  -h, --help
EOF
  }

  local TEMP server_url dest user
  TEMP=$(getopt -o hd:u: --long help,url:,dest:,user: -n 'download' -- "$@") || return 1
  eval set -- "$TEMP"

  while true; do
    case "$1" in
      --url)      url="$2";   shift 2 ;;
      -d|--dest)  dest="$2";  shift 2 ;;
      -u|--user)  user="$2";  shift 2 ;;
      -h|--help)
        print_download_help
        return 0 ;;
      --) shift; break ;;
      *)  print_download_help; fatal "Unexpected option $1" ;;
    esac
  done

  # Default fallbacks
  [[ -z "${dest:-}" ]] && dest="${MC_INSTANCES}/${MC_NAME}"
  [[ -z "${user:-}"   ]] && user="${MC_USER}"
  [[ -d "$dest" ]] || fatal "Destination directory '$dest' does not exist."
  id -u "$user" >/dev/null 2>&1 || fatal "User '$user' not found."

  # Install required packages
  require_packages_apt -i curl jq

  info "Destination: $dest, User: $user"

  # resolve download URL & expected SHA1
  local latest_ver expected_sha1
  if [[ -n "${url:-}" ]]; then
    info "--url provided; using custom download."
    latest_ver="custom"
    expected_sha1="SKIP"
  else
    info "Fetching latest vanilla metadata …"
    read -r latest_ver url expected_sha1 <<<"$(get_latest_server_meta)" || \
      fatal "Failed to retrieve metadata."
  fi

  # determine paths
  local jar_name
  if [[ "$latest_ver" == "custom" ]]; then
    jar_name="$(basename "$url")"
  else
    jar_name="minecraft_server_${latest_ver}.jar"
  fi
  local jar_path="${dest}/${jar_name}"

  # helper: verify SHA1
  verify_checksum() {  # $1=file  $2=sha1
    local actual
    actual=$(sha1sum "$1" | awk '{print $1}')
    [[ "$2" == "$actual" ]]
  }

  # existing file check
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

  # download & verify
  info "Downloading $(basename "$jar_path") …"
  if ! sudo -u "$user" curl -fLs -o "$jar_path" "$url"; then
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