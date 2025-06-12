#!/bin/bash

set -e

manifest_url="https://piston-meta.mojang.com/mc/game/version_manifest.json"

# Get the latest stable version
latest_version=$(curl -s "$manifest_url" | jq -r '.latest.release')
version_url=$(curl -s "$manifest_url" | jq -r --arg ver "$latest_version" '.versions[] | select(.id == $ver) | .url')
metadata=$(curl -s "$version_url")

server_jar_url=$(echo "$metadata" | jq -r '.downloads.server.url')
expected_sha1=$(echo "$metadata" | jq -r '.downloads.server.sha1')
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
    exit 0
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

sudo chown minecraft: "$jar_name"
sudo chmod 644 "$jar_name"

sudo -u minecraft ln -sf "$(realpath "$jar_name")" /opt/minecraft/server/vanilla/server.jar
