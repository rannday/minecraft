#!/usr/bin/env bash
# shellcheck source=src/env.sh
# shellcheck source=src/utils.sh
set -euo pipefail
trap 'echo "Interrupted. Exiting."; exit 1' INT TERM
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && { echo "Run, don’t source."; return 1; }

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SRC_DIR/env.sh"
source "$SRC_DIR/utils.sh"

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --target, -t DIR   Download target directory (default: \$SRV_DIR from env.sh)
  --user,   -u USER  Run curl as USER instead of default MC_USER
  --help,   -h       Show this help message and exit
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target) SRV_DIR="$2"; shift 2 ;;
    -u|--user)   MC_USER="$2"; shift 2 ;;
    -h|--help)   print_usage;  exit 0 ;;
    *) echo "Unknown option: $1"; print_usage; exit 1 ;;
  esac
done

[[ -d "$SRV_DIR" ]] || { echo "Error: Target directory $SRV_DIR does not exist."; exit 1; }

read -r latest_ver server_url expected_sha1 <<<"$(get_latest_server_meta)" || {
  echo "Error: Failed to retrieve latest server metadata."; exit 1; }

jar_name="minecraft_server_${latest_ver}.jar"
jar_path="$SRV_DIR/$jar_name"
export SRV_JAR="$jar_path"

verify_checksum() {
  # $1 = file path, $2 = expected sha1
  local actual
  actual=$(sha1sum "$1" | awk '{print $1}')
  [[ "$2" == "$actual" ]]
}

download_and_verify() {
  echo "Downloading $jar_name → $SRV_DIR ..."
  if ! sudo -u "$MC_USER" curl -fLs -o "$jar_path" "$server_url"; then
    echo "Error: failed to download JAR."; return 1
  fi

  echo "Verifying download checksum ..."
  if ! verify_checksum "$jar_path" "$expected_sha1"; then
    echo "Checksum mismatch after download."; return 1
  fi
  echo "Download checksum OK."
}

if [[ -f "$jar_path" ]]; then
  echo "Downloaded file $jar_name already exists. Verifying ..."
  if verify_checksum "$jar_path" "$expected_sha1"; then
    echo "Downloaded file is valid - nothing to do."
    exit 0
  else
    echo "Downloaded file failed checksum. Re-downloading ..."
    sudo -u "$MC_USER" rm -f "$jar_path"
  fi
fi

download_and_verify || { echo "Download failed."; exit 1; }

echo "Download done - JAR: $jar_path"