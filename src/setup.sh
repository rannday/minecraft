#!/usr/bin/env bash
# shellcheck source=src/env.sh
# shellcheck source=src/utils.sh
set -euo pipefail
trap 'echo "Interrupted. Exiting."; exit 1' INT TERM
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && {
  echo "This script should be executed, not sourced."
  return 1
}

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SRC_DIR/env.sh"        
source "$SRC_DIR/utils.sh"  

usage() {
  cat <<EOF
Usage: ./setup.sh [options]

Options:
  --motd         TEXT   Message of the day
  --port         NUM    Server port
  --ram          SIZE   Heap size for -Xms/-Xmx (e.g. 8G, 16384M)
  --gamemode     MODE   survival | creative | adventure
  --pvp          BOOL   Enable or disable PvP (default: true)
  --whitelist    LIST   Comma-separated player names to pre-fill whitelist
  --user         USER   Override default MC_USER from env.sh
  --help, -h
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --motd)        MC_MOTD="$2";       shift 2 ;;
    --port)        MC_PORT="$2";       shift 2 ;;
    --ram)         MC_RAM="$2";        shift 2 ;;
    --gamemode)    MC_GAMEMODE="$2";   shift 2 ;;
    --pvp)         MC_PVP="$2";        shift 2 ;;
    --whitelist)   MC_WHITELIST="$2";  shift 2 ;;
    --user)        MC_USER="$2";       shift 2 ;;
    -h|--help)     usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

case "$MC_GAMEMODE" in
  survival|creative|adventure) ;;
  *) echo "Invalid --gamemode: $MC_GAMEMODE"; exit 1 ;;
esac

export SRV_DIR="$SRV_BASE/$MC_GAMEMODE"
export SRV_JAR="$SRV_DIR/server.jar"
export JVM_ARGS_FILE="$SRV_DIR/jvm.args"
export SERVICE_NAME="mc-${MC_GAMEMODE}"
export TMUX_SESSION="$SERVICE_NAME"

# Compute MAX_PLAYERS from RAM + ratio
players_per_gb="${MC_PLAYERS_PER_GB:-1}"

if [[ "$MC_RAM" =~ ^([0-9]+)([GgMm])$ ]]; then
  mem=${BASH_REMATCH[1]}
  unit=${BASH_REMATCH[2]}

  # Always convert MiB, then floor to 1 GiB
  if [[ "$unit" =~ [Mm] ]]; then
    mem=$(( mem / 1024 ))
  fi
  (( mem < 1 )) && mem=1
  (( players_per_gb < 1 )) && players_per_gb=1

  MAX_PLAYERS=$(( mem * players_per_gb ))
  (( MAX_PLAYERS > 100 )) && MAX_PLAYERS=100
else
  MAX_PLAYERS=10
  echo "WARNING: Could not parse MC_RAM='$MC_RAM'; using fallback MAX_PLAYERS=$MAX_PLAYERS"
fi
echo "max-players set to $MAX_PLAYERS (${mem:-?} GiB @ ${players_per_gb} players/GiB)"

if ! id "$MC_USER" &>/dev/null; then
  sudo adduser --system --home "$MC_HOME" --shell /bin/bash --group "$MC_USER"
fi

sudo mkdir -p "$SRV_DIR"
sudo chown -R "$MC_USER:$MC_USER" "$MC_HOME"

[[ -f "$SRC_DIR/java.sh" ]]     && "$SRC_DIR/java.sh"
[[ -f "$SRC_DIR/download.sh" ]] && "$SRC_DIR/download.sh" --target "$SRV_DIR" --username "$MC_USER"

eula_file="$SRV_DIR/eula.txt"
grep -q 'eula=true' "$eula_file" 2>/dev/null || \
  sudo -u "$MC_USER" bash -c "echo 'eula=true' > '$eula_file'"

WHITELIST_ENABLED=false
[[ -n "${MC_WHITELIST:-}" ]] && WHITELIST_ENABLED=true

sudo -u "$MC_USER" tee "$SRV_DIR/server.properties" >/dev/null <<EOF
enforce-whitelist=${WHITELIST_ENABLED}
force-gamemode=true
gamemode=${MC_GAMEMODE}
max-players=${MAX_PLAYERS}
online-mode=true
pvp=${MC_PVP}
server-port=${MC_PORT}
white-list=${WHITELIST_ENABLED}
motd=${MC_MOTD}
EOF

sudo -u "$MC_USER" tee "$SRV_DIR/jvm.args" >/dev/null <<EOF
-Xms${MC_RAM}
-Xmx${MC_RAM}
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

echo "Setup complete — server files in $SRV_DIR"
