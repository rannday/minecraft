#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Setup interrupted. Exiting."; exit 1' INT TERM

MOTD="Minecraft Server"
PORT=25565
RAM="4G"
GAMEMODE="survival"
PVP=true
WHITELIST=""

MC_HOME="/opt/minecraft"
SRV_DIR="${MC_BASE}/server/"

# PARSER
usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --motd         TEXT   Message of the day
  --port         NUM    Server port
  --ram          SIZE   Heap size for -Xms / -Xmx (e.g. 8G, 16384M)
  --gamemode     MODE   Game mode (survival|creative|adventure)
  --pvp          BOOL   Enable or disable PvP (default: true)
  --whitelist    LIST   Comma-separated player names to pre-fill whitelist
  -h, --help            Show this help and exit
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --motd)        MOTD="$2";         shift 2 ;;
    --port)        PORT="$2";         shift 2 ;;
    --ram)         RAM="$2";          shift 2 ;;
    --gamemode)    GAMEMODE="$2";     shift 2 ;;
    --pvp)         PVP="$2";          shift 2 ;;
    --whitelist)   WHITELIST="$2";    shift 2 ;;
    -h|--help)     usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# INSTALL PREREQUISITES
sudo apt update
sudo apt upgrade -y
sudo apt install -y curl tmux jq git

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR"

# INSTALL JAVA
if [[ -f "${SCRIPTS_DIR}/install-java.sh" ]]; then
  "${SCRIPTS_DIR}/install-java.sh"
else
  echo "Warning: install-java.sh not found in ${SCRIPTS_DIR}"
fi

# SETUP USER
if ! id minecraft &>/dev/null; then
  echo "Creating 'minecraft' system user..."
  sudo adduser --system --home /opt/minecraft --shell /bin/bash --group minecraft
else
  echo "'minecraft' user already exists."
fi

if [ ! -d /opt/minecraft ]; then
  echo "Creating /opt/minecraft..."
  sudo mkdir -p /opt/minecraft
fi

sudo chown -R minecraft:minecraft /opt/minecraft
sudo -u minecraft mkdir -p /opt/minecraft/server/vanilla

if [[ -f "${SCRIPTS_DIR}/download.sh" ]]; then
  "${SCRIPTS_DIR}/download.sh"
else
  echo "Warning: download.sh not found in ${SCRIPTS_DIR}"
fi

eula_file="/opt/minecraft/server/vanilla/eula.txt"
if ! grep -q 'eula=true' "$eula_file" 2>/dev/null; then
  sudo -u minecraft bash -c 'echo "eula=true" > /opt/minecraft/server/vanilla/eula.txt'
fi

WHITELIST_ENABLED=false
[[ -n "$WHITELIST" ]] && WHITELIST_ENABLED=true

properties_file="/opt/minecraft/server/vanilla/server.properties"
if [ ! -f "$properties_file" ]; then
  echo "Creating default server.properties at $properties_file..."
  sudo -u minecraft tee "$properties_file" > /dev/null <<EOF
enforce-whitelist=${WHITELIST_ENABLED}
force-gamemode=true
gamemode=${GAMEMODE}
max-players=20
online-mode=true
pvp=${PVP}
server-port=${PORT}
white-list=${WHITELIST_ENABLED}
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
