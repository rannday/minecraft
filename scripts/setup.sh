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
SRV_DIR="${MC_HOME}/server/${GAMEMODE}"

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --motd         TEXT   Message of the day
  --port         NUM    Server port
  --ram          SIZE   Heap size for -Xms / -Xmx (e.g. 8G, 16384M)
  --gamemode     MODE   survival | creative | adventure
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

case "$GAMEMODE" in
  survival|creative|adventure) ;;
  *) echo "Invalid --gamemode: $GAMEMODE"; exit 1 ;;
esac

SRV_DIR="${MC_HOME}/server/${GAMEMODE}"

sudo apt update
sudo apt upgrade -y
sudo apt install -y curl tmux jq git

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

[[ -f "${SCRIPT_DIR}/install-java.sh" ]] && "${SCRIPT_DIR}/install-java.sh"

if ! id minecraft &>/dev/null; then
  sudo adduser --system --home "$MC_HOME" --shell /bin/bash --group minecraft
fi

sudo mkdir -p "$SRV_DIR"
sudo chown -R minecraft:minecraft "$MC_HOME"

# (download.sh currently hard-codes SERVER_DIR; update it later or export var)
export SERVER_DIR="$SRV_DIR"
[[ -f "${SCRIPT_DIR}/download.sh" ]] && "${SCRIPT_DIR}/download.sh"

eula_file="$SRV_DIR/eula.txt"
grep -q 'eula=true' "$eula_file" 2>/dev/null || \
  sudo -u minecraft bash -c "echo 'eula=true' > '$eula_file'"

WHITELIST_ENABLED=false
[[ -n "$WHITELIST" ]] && WHITELIST_ENABLED=true

properties_file="$SRV_DIR/server.properties"
if [[ ! -f "$properties_file" ]]; then
  sudo -u minecraft tee "$properties_file" >/dev/null <<EOF
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
fi

jvm_args_file="$SRV_DIR/jvm.args"
if [[ ! -f "$jvm_args_file" ]]; then
  sudo -u minecraft tee "$jvm_args_file" >/dev/null <<EOF
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
fi

echo "Setup complete — server files in $SRV_DIR"
