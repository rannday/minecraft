#!/bin/bash

# Fetch the version manifest
manifest_url="https://piston-meta.mojang.com/mc/game/version_manifest.json"
latest_version=$(curl -s "$manifest_url" | jq -r '.latest.release')

# Get the download metadata for the latest version
version_url=$(curl -s "$manifest_url" | jq -r --arg ver "$latest_version" '.versions[] | select(.id == $ver) | .url')

# Get the server download link
server_jar_url=$(curl -s "$version_url" | jq -r '.downloads.server.url')

# Download the server JAR
curl -o "minecraft_server_${latest_version}.jar" "$server_jar_url"

echo "Downloaded Minecraft server version $latest_version"
