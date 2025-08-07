#!/usr/bin/env bash
set -euo pipefail
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && { echo "Run, do not source." >&2; exit 1; }
BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$BASE_DIR/lib/log.sh"
trap 'warn "Interrupted. Exiting."; exit 1' INT TERM

source "$BASE_DIR/lib/apt_check.sh"
apt_requirements_check

set -a
source "$BASE_DIR/mc.env"
set +a

################################################################################
# Download Minecraft
################################################################################

download() {
  local url="$1"
  local dest="$2"
  local user="$3"

  [[ -z "$dest" ]] && dest="${MC_INSTANCES}/${MC_NAME}"
  [[ -z "$user" ]] && user="${MC_USER}"
  [[ -d "$dest" ]] || fatal "Destination directory '$dest' does not exist."
  id -u "$user" >/dev/null 2>&1 || fatal "User '$user' not found."

  require_packages_apt -i curl jq

  info "Destination: $dest, User: $user"

  local latest_ver expected_sha1
  if [[ -n "$url" ]]; then
    info "--url provided; using custom download."
    latest_ver="custom"
    expected_sha1="SKIP"
  else
    info "Fetching latest vanilla metadata …"
    read -r latest_ver url expected_sha1 <<<"$(get_latest_server_meta)" || \
      fatal "Failed to retrieve metadata."
  fi

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

print_usage() {
  cat <<EOF
Download Minecraft Server JAR
-----------------------------
Usage: $(basename "$0") download [options]

       --url   URL   Custom URL for server JAR
  -d, --dest   DIR   Destination directory (default: $MC_INSTANCES/$MC_NAME)
  -u, --user   USER  Run curl as USER (default: $MC_USER)
  -h, --help
EOF
}

[[ $# -lt 1 ]] && { print_usage; exit 1; }

COMMAND="$1"
shift

case "$COMMAND" in
  download)
    TEMP=$(getopt -o hd:u: --long help,url:,dest:,user: -n 'download' -- "$@") || exit 1
    eval set -- "$TEMP"

    url="" dest="" user=""
    while true; do
      case "$1" in
        --url)      url="$2";   shift 2 ;;
        -d|--dest)  dest="$2";  shift 2 ;;
        -u|--user)  user="$2";  shift 2 ;;
        -h|--help)  print_usage; exit 0 ;;
        --) shift; break ;;
        *)  print_usage; fatal "Unexpected option $1" ;;
      esac
    done

    download "$url" "$dest" "$user"
    ;;
  help|-h|--help)
    print_usage
    exit 0
    ;;
  *)
    error "Unknown command: $COMMAND"
    echo
    print_usage
    exit 1
    ;;
esac

exit 0