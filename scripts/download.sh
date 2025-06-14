#!/bin/bash

set -e
trap 'echo "Script interrupted. Exiting."; exit 1' INT TERM

# Constants
SERVER_DIR="/opt/minecraft/server/vanilla"
link_path="$SERVER_DIR/server.jar"

# Ensure user and directory exist
if ! id minecraft &>/dev/null; then
  echo "Error: 'minecraft' user does not exist. Run setup.sh first."
  exit 1
fi

if [ ! -d "$SERVER_DIR" ]; then
  echo "Error: Target directory $SERVER_DIR does not exist."
  exit 1
fi

# Check dependencies
for cmd in curl jq sha1sum realpath; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is not installed. Aborting."
    exit 1
  fi
done

# Get latest version info from Mojang
manifest_url="https://piston-meta.mojang.com/mc/game/version_manifest.json"
latest_version=$(curl -s "$manifest_url" | jq -r '.latest.release')
version_url=$(curl -s "$manifest_url" | jq -r --arg ver "$latest_version" '.versions[] | select(.id == $ver) | .url')

if [ -z "$latest_version" ] || [ -z "$version_url" ]; then
  echo "Error: Failed to fetch or parse version metadata."
  exit 1
fi

metadata=$(curl -s "$version_url")
server_jar_url=$(echo "$metadata" | jq -r '.downloads.server.url')
expected_sha1=$(echo "$metadata" | jq -r '.downloads.server.sha1')

if [ -z "$server_jar_url" ] || [ -z "$expected_sha1" ]; then
  echo "Error: Incomplete server metadata. Aborting."
  exit 1
fi

jar_name="minecraft_server_${latest_version}.jar"
jar_path="$SERVER_DIR/$jar_name"

# Download and verify JAR
download_and_verify() {
  echo "Downloading $jar_name into $SERVER_DIR..."
  if ! sudo curl -f -s -o "$jar_path" "$server_jar_url"; then
    echo "Error: Failed to download JAR from $server_jar_url"
    return 1
  fi

  echo "Verifying SHA1 checksum..."
  if [ ! -f "$jar_path" ]; then
    echo "Error: Downloaded file missing at $jar_path"
    return 1
  fi

  actual_sha1=$(sha1sum "$jar_path" | awk '{print $1}')

  if [ "$expected_sha1" != "$actual_sha1" ]; then
    echo "Checksum mismatch. Expected: $expected_sha1, Got: $actual_sha1"
    return 1
  fi

  echo "Checksum verified."
  return 0
}

# Check existing file or download
if [ -f "$jar_path" ]; then
  echo "$jar_name already exists in $SERVER_DIR. Verifying..."
  actual_sha1=$(sha1sum "$jar_path" | awk '{print $1}')
  if [ "$expected_sha1" == "$actual_sha1" ]; then
    echo "Existing file is valid. No download needed."
  else
    echo "Existing file failed checksum. Re-downloading..."
    rm -f "$jar_path"
    if ! download_and_verify; then
      echo "Re-download failed. Aborting."
      exit 1
    fi
  fi
else
  if ! download_and_verify; then
    echo "Download failed. Aborting."
    exit 1
  fi
fi

# Set ownership and permissions
sudo chown minecraft:minecraft "$jar_path"
sudo chmod 644 "$jar_path"

# Symlink management
if [ -L "$link_path" ]; then
  current_target=$(readlink -f "$link_path")
  if [ "$current_target" == "$jar_path" ]; then
    echo "Symlink already correct: $link_path -> $jar_path"
  else
    echo "Fixing incorrect symlink (was pointing to $current_target)..."
    sudo -u minecraft ln -sf "$jar_path" "$link_path"
    echo "Symlink updated: $link_path -> $jar_path"
  fi
else
  echo "Creating symlink: $link_path -> $jar_path"
  sudo -u minecraft ln -sf "$jar_path" "$link_path"
fi

# Summary
echo "Done."
echo "JAR: $jar_path"
echo "Symlink: $link_path -> $(readlink -f "$link_path")"
