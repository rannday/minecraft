#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Setup interrupted. Exiting."; exit 1' INT TERM

MOTD="Minecraft Server"
PORT=25565
RAM="8G"
GAMEMODE="survival"
CONF_FILE=""

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -f, --config   FILE   Load variables from FILE (shell VAR=VALUE format)
  --motd         TEXT   Message of the day
  --port         NUM    Server port
  --ram          SIZE   Heap size for -Xms / -Xmx (e.g. 8G, 16384M)
  --gamemode     MODE   Game mode (survival|creative|adventure|spectator)
  -h, --help            Show this help and exit
EOF
  exit 1
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${ROOT_DIR}/scripts"

if [[ $# -gt 0 ]]; then
  # detect -f FILE early to source before other flags
  for ((i=1; i<=$#; i++)); do
    case "${!i}" in
      -f|--config)
        NEXT_IDX=$((i+1))
        CONF_FILE="${!NEXT_IDX}"
        ;;
    esac
  done
fi

if [[ -n "$CONF_FILE" ]]; then
  if [[ -f "$CONF_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONF_FILE"
  else
    echo "Config file $CONF_FILE not found"; exit 1
  fi
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--config)   shift 2 ;;                  # already handled
    --motd)        MOTD="$2";      shift 2 ;;
    --port)        PORT="$2";      shift 2 ;;
    --ram)         RAM="$2";       shift 2 ;;
    --gamemode)    GAMEMODE="$2";  shift 2 ;;
    -h|--help)     usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

sudo apt update
sudo apt upgrade -y
sudo apt install -y curl tmux jq git

cd "$(dirname "$0")"
if [ -f ./install-java.sh ]; then
  ./install-java.sh
else
  echo "Warning: install-java.sh not found in $(pwd)"
fi

if ! id minecraft &>/dev/null; then
  echo "Creating 'minecraft' system user..."
  sudo adduser --system --home /opt/minecraft --shell /bin/bash --group minecraft
else
  echo "'minecraft' user already exists."
fi

# Ensure /opt/minecraft exists and has proper ownership
if [ ! -d /opt/minecraft ]; then
  echo "Creating /opt/minecraft..."
  sudo mkdir -p /opt/minecraft
fi

sudo chown -R minecraft:minecraft /opt/minecraft

sudo -u minecraft mkdir -p /opt/minecraft/server/vanilla

cd "$(dirname "$0")"
if [ -f ./download.sh ]; then
  ./download.sh
else
  echo "Warning: download.sh not found in $(pwd)"
fi

eula_file="/opt/minecraft/server/vanilla/eula.txt"
if ! grep -q 'eula=true' "$eula_file" 2>/dev/null; then
  sudo -u minecraft bash -c 'echo "eula=true" > /opt/minecraft/server/vanilla/eula.txt'
fi

properties_file="/opt/minecraft/server/vanilla/server.properties"
if [ ! -f "$properties_file" ]; then
  echo "Creating default server.properties at $properties_file..."
  sudo -u minecraft tee "$properties_file" > /dev/null <<EOF
enforce-whitelist=true
force-gamemode=true
gamemode=survival
max-players=20
online-mode=true
pvp=true
server-port=${PORT}
white-list=true
motd=${MOTD}
EOF
else
  echo "server.properties already exists — skipping."
fi

jvm_args_file="/opt/minecraft/server/vanilla/jvm.args"

if [ ! -f "$jvm_args_file" ]; then
  echo "Creating default JVM args at $jvm_args_file..."
  sudo -u minecraft tee "$jvm_args_file" > /dev/null <<EOF
-Xms${RAM}
-Xmx${RAM}
-XX:+UseG1GC
-XX:+ParallelRefProcEnabled
-XX:MaxGCPauseMillis=200
-XX:+UnlockExperimentalVMOptions
-XX:+DisableExplicitGC
-XX:+AlwaysPreTouch
-XX:G1NewSizePercent=30
-XX:G1MaxNewSizePercent=40
-XX:G1HeapRegionSize=16M
-XX:G1ReservePercent=20
-XX:G1HeapWastePercent=5
-XX:G1MixedGCCountTarget=4
-XX:InitiatingHeapOccupancyPercent=15
-XX:SurvivorRatio=32
-XX:+PerfDisableSharedMem
-XX:MaxTenuringThreshold=1
-Dusing.aikars.flags=https://mcflags.emc.gs
-Daikars.new.flags=true
EOF
else
  echo "JVM args file already exists at $jvm_args_file — skipping."
fi
