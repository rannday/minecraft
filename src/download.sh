#!/usr/bin/env bash
# shellcheck source=src/env.sh
# shellcheck source=src/utils.sh
set -euo pipefail
trap 'echo "Interrupted. Exiting."; exit 1' INT TERM
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && { echo "Run, don’t source."; return 1; }

DEST=""
OWNER=""

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --target,   -t DIR   Override download target directory
  --username, -u USER  Override default MC_USER from env.sh
  --help,     -h       Show this help message and exit
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)   DEST="$2"; shift 2 ;;
    -u|--username) OWNER="$2"; shift 2 ;;
    -h|--help)     print_usage ;;
    *) echo "Unknown option: $1"; print_usage ;;
  esac
done

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SRC_DIR/env.sh"        
source "$SRC_DIR/utils.sh"  

[[ -n "$OWNER" ]] && MC_USER="$OWNER"
[[ -n "$DEST" ]] && SRV_DIR="$DEST"

[[ -d "$SRV_DIR" ]] || {
  echo "Error: Target directory $SRV_DIR does not exist."
  exit 1
}

require_packages curl jq

manifest_url="$MC_VERSION_MANIFEST_URL"
latest_version=$(curl -s "$manifest_url" | jq -r '.latest.release')
version_url=$(curl -s "$manifest_url" | jq -r --arg ver "$latest_version" '.versions[] | select(.id == $ver) | .url')

metadata=$(curl -s "$version_url")
server_jar_url=$(echo "$metadata" | jq -r '.downloads.server.url')
expected_sha1=$(echo "$metadata"  | jq -r '.downloads.server.sha1')

[[ -n "$server_jar_url" && -n "$expected_sha1" ]] || {
  echo "Error: Incomplete server metadata. Aborting."
  exit 1
}

jar_name="minecraft_server_${latest_version}.jar"
jar_path="$SRV_DIR/$jar_name"
export SRV_JAR="$jar_path"

download_and_verify() {
  echo "Downloading $jar_name into $SRV_DIR..."
  if ! sudo -u "$MC_USER" curl -f -L -s -o "$jar_path" "$server_jar_url"; then
    echo "Error: Failed to download JAR from $server_jar_url"
    return 1
  fi

  echo "Verifying SHA1 checksum..."
  actual_sha1=$(sha1sum "$jar_path" | awk '{print $1}')
  if [[ "$expected_sha1" != "$actual_sha1" ]]; then
    echo "Checksum mismatch. Expected: $expected_sha1, Got: $actual_sha1"
    return 1
  fi
  echo "Checksum verified."
  return 0
}

if [[ -f "$jar_path" ]]; then
  echo "$jar_name already exists. Verifying..."
  actual_sha1=$(sha1sum "$jar_path" | awk '{print $1}')
  if [[ "$expected_sha1" != "$actual_sha1" ]]; then
    echo "Existing file failed checksum. Re-downloading..."
    sudo -u "$MC_USER" rm -f "$jar_path"
    download_and_verify || { echo "Re-download failed."; exit 1; }
  else
    echo "Existing file is valid. No download needed."
  fi
else
  download_and_verify || { echo "Download failed."; exit 1; }
fi

echo "Done - JAR: $jar_path"
