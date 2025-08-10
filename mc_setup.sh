#!/usr/bin/env bash
set -euo pipefail
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && { echo "Run, do not source." >&2; exit 1; }
BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$BASE_DIR/lib/log.sh"
trap 'warn "Interrupted. Exiting."; exit 1' INT TERM

source "$BASE_DIR/lib/apt.sh"
apt_requirements_check

set -a
source "$BASE_DIR/mc.env"
set +a

source "$BASE_DIR/lib/download.sh"
source "$BASE_DIR/lib/java.sh"

[[ "$MC_GAMEMODE" =~ ^(survival|creative|adventure)$ ]] || fatal "Invalid gamemode '$MC_GAMEMODE'"

if ! [[ "$MC_PORT" =~ ^[0-9]+$ ]] || (( MC_PORT < 1024 || MC_PORT > 65535 )); then
  fatal "Invalid port '$MC_PORT'. Must be a number between 1024–65535."
fi
if ss -tln sport = :$MC_PORT | grep -q LISTEN; then
  fatal "$(cat <<EOF
Port $MC_PORT is already in use. Choose a different port using MC_PORT in mc.env

To see what's using the port:
  sudo lsof -iTCP:$MC_PORT -sTCP:LISTEN
  sudo ss -tuln | grep $MC_PORT
EOF
)"
fi

SRV_DIR="${MC_INSTANCES}/${MC_NAME}"
SRV_JAR="${SRV_DIR}/server.jar"
JVM_ARGS_FILE="${SRV_DIR}/jvm.args"
META_ENV_FILE="${SRV_DIR}/meta.env"

players=10
if [[ "$MC_RAM" =~ ^([0-9]+)([GgMm])$ ]]; then
  mem="${BASH_REMATCH[1]}"
  unit="${BASH_REMATCH[2]}"
  [[ "$unit" =~ [Mm] ]] && mem=$(( mem / 1024 ))
  (( mem < 1 )) && mem=1
  (( MC_RAM_RATIO < 1 )) && MC_RAM_RATIO=1
  players=$(( mem * MC_RAM_RATIO ))
  (( players > 100 )) && players=100
else
  warn "Could not parse MC_RAM; defaulting max-players=${players}"
fi

if getent passwd "$MC_USER" >/dev/null 2>&1; then
  current_home="$(getent passwd "$MC_USER" | cut -d: -f6)"
  if [[ "$current_home" != "$MC_HOME" ]]; then
    fatal "$(cat <<EOF
User '$MC_USER' already exists with home '$current_home', expected: '$MC_HOME'

Fix it manually using one of the following:

  • Change home:
      sudo usermod -d $MC_HOME -m $MC_USER

  • Or delete and recreate:
      sudo /sbin/deluser --remove-home $MC_USER
      sudo /sbin/delgroup --only-if-empty $MC_USER

  • Then verify:
      getent passwd $MC_USER
      getent group  $MC_USER
EOF
)"
  fi
  info "Using existing user '$MC_USER' (home: $current_home)"
else
  info "Creating system user '$MC_USER' with home '$MC_HOME'"
  sudo adduser --system --home "$MC_HOME" --shell /bin/bash --group "$MC_USER"
fi

for dir in "$MC_BIN" "$MC_BACKUPS" "$SRV_DIR"; do
  if [[ ! -d "$dir" ]]; then
    sudo mkdir -p "$dir"
    sudo chown -R "$MC_USER:$MC_USER" "$dir"
  fi
done

get_latest_jar() { find "$1" -maxdepth 1 -name 'minecraft_server_*.jar' | sort -Vr | head -n1; }

latest=""
latest=$(get_latest_jar "$SRV_DIR" || true)
if [[ -z "$latest" ]]; then
  info "No server JAR found — downloading latest vanilla release …"
  download "" "$SRV_DIR" "$MC_USER"
  latest=$(get_latest_jar "$SRV_DIR")
  [[ -z "$latest" ]] && fatal "Download failed: no JAR present in $SRV_DIR"
else
  info "Existing server JAR found: $(basename "$latest")"
fi

sudo -u "$MC_USER" ln -sf "$(basename "$latest")" "$SRV_JAR"
sudo -u "$MC_USER" bash -c "echo 'eula=true' > '${SRV_DIR}/eula.txt'"

wl_enabled=false
[[ -n "${MC_WHITELIST:-}" ]] && wl_enabled=true
sudo -u "$MC_USER" tee "${SRV_DIR}/server.properties" >/dev/null <<EOF
enforce-whitelist=${wl_enabled}
force-gamemode=true
gamemode=${MC_GAMEMODE}
max-players=${players}
online-mode=true
pvp=${MC_PVP}
server-port=${MC_PORT}
white-list=${wl_enabled}
motd=${MC_MOTD}
EOF

sudo -u "$MC_USER" tee "$JVM_ARGS_FILE" >/dev/null <<EOF
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

cat <<EOF | sudo -u "$MC_USER" tee "$META_ENV_FILE" >/dev/null
NAME=$MC_NAME
PORT=$MC_PORT
MOTD="$MC_MOTD"
RAM=$MC_RAM
GAMEMODE=$MC_GAMEMODE
WHITELIST=$MC_WHITELIST
EOF

info "Setup complete — instance files in ${SRV_DIR}"
info "Start with: sudo -u ${MC_USER} ${TEMURIN_JAVA_BIN_PATH}/java \$(cat ${JVM_ARGS_FILE}) -jar ${SRV_JAR} nogui"
