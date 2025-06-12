#!/bin/bash

set -e
trap 'echo "Script interrupted. Exiting."; exit 1' INT TERM

if ! id minecraft &>/dev/null; then
  echo "Error: 'minecraft' user does not exist. Run setup.sh first."
  exit 1
fi

link_path="/opt/minecraft/server/vanilla/server.jar"

if [ ! -d "$(dirname "$link_path")" ]; then
  echo "Error: Target directory $(dirname "$link_path") does not exist."
  exit 1
fi

for cmd in curl jq sha1sum realpath; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is not installed. Aborting."
    exit 1
  fi
done

manifest_url="https://piston-meta.mojang.com/mc/game/version_manifest.json"

# Get the latest stable version
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

download_and_verify() {
  echo "Downloading $jar_name..."
  curl -s -o "$jar_name" "$server_jar_url"

  echo "Verifying SHA1 checksum..."
  actual_sha1=$(sha1sum "$jar_name" | awk '{print $1}')

  if [ "$expected_sha1" != "$actual_sha1" ]; then
    echo "Checksum mismatch. Expected: $expected_sha1, Got: $actual_sha1"
    return 1
  fi

  echo "Checksum verified."
  return 0
}

# Check if file already exists and is valid
if [ -f "$jar_name" ]; then
  echo "$jar_name already exists. Verifying..."
  actual_sha1=$(sha1sum "$jar_name" | awk '{print $1}')
  if [ "$expected_sha1" == "$actual_sha1" ]; then
    echo "Existing file is valid. No download needed."
  else
    echo "Existing file failed checksum. Re-downloading..."
    rm -f "$jar_name"
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

# Fix permissions
sudo chown minecraft:minecraft "$jar_name"
sudo chmod 644 "$jar_name"

# Resolve the full path to the JAR
jar_path="$(realpath "$jar_name")"

# Check if symlink exists and points to the right target
if [ -L "$link_path" ]; then
  current_target=$(readlink -f "$link_path")
  if [ "$current_target" == "$jar_path" ]; then
    echo "Symlink already exists and is correct: $link_path -> $jar_path"
  else
    echo "Symlink exists but points to $current_target — fixing..."
    sudo -u minecraft ln -sf "$jar_path" "$link_path"
    echo "Updated symlink: $link_path -> $jar_path"
  fi
else
  echo "Symlink does not exist — creating..."
  sudo -u minecraft ln -sf "$jar_path" "$link_path"
  echo "Created symlink: $link_path -> $jar_path"
fi

echo "Done."
echo "JAR: $jar_path"
echo "Symlink: $link_path -> $(readlink -f "$link_path")"
