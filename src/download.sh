#!/usr/bin/env bash
# shellcheck source=env.sh
# shellcheck source=utils.sh
set -euo pipefail
trap 'echo "Interrupted. Exiting."; exit 1' INT TERM
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && {
  echo "This script should be executed, not sourced."
  return 1
}

DEST=""
print_usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -d, --destination DIR   Override download target directory
  -h, --help              Show this help message and exit
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--destination)
      DEST="$2"
      shift 2
      ;;
    -h|--help)
      print_usage
      ;;
    *)
      echo "Unknown option: $1"
      print_usage
      ;;
  esac
done

SRC_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SRC_DIR}/env.sh" 
source "${SRC_DIR}/utils.sh"

[[ -n "$DEST" ]] && SRV_DIR="$DEST"
SRV_JAR="$SRV_DIR/server.jar"

if ! id "$MC_USER" &>/dev/null; then
  echo "Error: '$MC_USER' user does not exist. Run setup.sh first."
  exit 1
fi

[[ -d "$SRV_DIR" ]] || {
  echo "Error: Target directory $SRV_DIR does not exist."
  exit 1
}

require_packages curl jq sha1sum

# Get latest version info from Mojang
manifest_url="$MC_VERSION_MANIFEST_URL"
latest_version=$(curl -s "$manifest_url" | jq -r '.latest.release')
version_url=$(curl -s "$manifest_url"  | jq -r --arg ver "$latest_version" \
                   '.versions[] | select(.id == $ver) | .url')

metadata=$(curl -s "$version_url")
server_jar_url=$(echo "$metadata" | jq -r '.downloads.server.url')
expected_sha1=$(echo "$metadata"  | jq -r '.downloads.server.sha1')

[[ -n "$server_jar_url" && -n "$expected_sha1" ]] || {
  echo "Error: Incomplete server metadata. Aborting."
  exit 1
}

jar_name="minecraft_server_${latest_version}.jar"
jar_path="$SRV_DIR/$jar_name"

download_and_verify() {
  echo "Downloading $jar_name into $SRV_DIR..."
  if ! sudo curl -f -s -o "$jar_path" "$server_jar_url"; then
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
    rm -f "$jar_path"
    download_and_verify || { echo "Re-download failed."; exit 1; }
  else
    echo "Existing file is valid. No download needed."
  fi
else
  download_and_verify || { echo "Download failed."; exit 1; }
fi

sudo chown "$MC_USER:$MC_USER" "$jar_path"
sudo chmod 644 "$jar_path"

if [[ -L "$SRV_JAR" ]]; then
  current_target=$(resolve_symlink "$SRV_JAR")
  if [[ "$current_target" == "$jar_path" ]]; then
    echo "Symlink already correct: $SRV_JAR -> $jar_path"
  else
    echo "Fixing incorrect symlink (was $current_target)..."
    sudo -u "$MC_USER" ln -sf "$jar_path" "$SRV_JAR"
    echo "Symlink updated."
  fi
else
  echo "Creating symlink: $SRV_JAR -> $jar_path"
  sudo -u "$MC_USER" ln -sf "$jar_path" "$SRV_JAR"
fi

echo "Done."
echo "JAR:      $jar_path"
resolved_target="$(resolve_symlink "$SRV_JAR" 2>/dev/null || echo "unresolved")"
echo "Symlink:  $SRV_JAR -> $resolved_target"

unset actual_sha1 metadata server_jar_url expected_sha1 latest_version version_url
