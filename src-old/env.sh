#!/usr/bin/env bash
set -euo pipefail
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
  echo "This script is meant to be sourced, not executed."
  exit 1
}

# Ensure this script is sourced only once
[[ "${ENV_SH_SOURCED:-}" == "yes" ]] && return 0
readonly ENV_SH_SOURCED=yes

# Minecraft base configuration
export MC_NAME="vanilla"
export MC_USER="minecraft"
export MC_HOME="/opt/minecraft"
export SRV_BASE="$MC_HOME/server"

# Java configuration
export REQUIRED_JAVA_VERSION="21"
JAVA_ARCH="$(dpkg --print-architecture)"
export JAVA_ARCH
export JAVA_BIN_PATH="/usr/lib/jvm/temurin-${REQUIRED_JAVA_VERSION}-jdk-${JAVA_ARCH}/bin"

# Default runtime settings (can be overridden)
export MC_MOTD="Minecraft Server"
export MC_PORT=25565
export MC_RAM="4G"
export MC_GAMEMODE="survival"
export MC_PVP="true"
export MC_WHITELIST=""

export MC_RAM_RATIO=1

# URL for Mojang manifest
export MC_VERSION_MANIFEST_URL="https://piston-meta.mojang.com/mc/game/version_manifest.json"
