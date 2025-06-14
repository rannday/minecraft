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
export MC_USER="minecraft"
export MC_HOME="/opt/minecraft"
export SRV_BASE="$MC_HOME/server"

# Java configuration
export REQUIRED_JAVA_VERSION="21"
export JAVA_ARCH="$(dpkg --print-architecture)"   # auto-detect: amd64 / arm64
export JAVA_BIN_PATH="/usr/lib/jvm/temurin-${REQUIRED_JAVA_VERSION}-jdk-${JAVA_ARCH}/bin"

# Default runtime settings (can be overridden)
export MC_MOTD="Minecraft Server"
export MC_PORT=25565
export MC_RAM="4G"
export MC_GAMEMODE="survival"
export MC_PVP="true"
export MC_WHITELIST=""

export MC_PLAYERS_PER_GB=1

# Derived directories (must override GAMEMODE before sourcing to affect SRV_DIR)
export GAMEMODE="${GAMEMODE:-$MC_GAMEMODE}"
export SRV_DIR="${SRV_BASE}/${GAMEMODE}"

# Server JAR and JVM args
export SRV_JAR="$SRV_DIR/server.jar"
export JVM_ARGS_FILE="$SRV_DIR/jvm.args"

# Systemd + Tmux service
export SERVICE_NAME="mc-${GAMEMODE}"
export TMUX_SESSION="${SERVICE_NAME}"

# URL for Mojang manifest
export MC_VERSION_MANIFEST_URL="https://piston-meta.mojang.com/mc/game/version_manifest.json"
