#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Interrupted. Exiting."; exit 1' INT TERM
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && { echo "Run, don’t source."; return 1; }

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SRC_DIR/env.sh"
source "$SRC_DIR/utils.sh"

# ── CLI parsing ────────────────────────────────────────────────
print_usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --mode, -m MODE   Gamemode to run (survival | creative | adventure)
  --help, -h
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--mode)  MC_GAMEMODE="$2"; shift 2 ;;
    -h|--help)  print_usage; exit 0 ;;
    *)          echo "Unknown option: $1"; print_usage; exit 1 ;;
  esac
done

case "$MC_GAMEMODE" in
  survival|creative|adventure) ;;
  *) echo "Invalid --mode: $MC_GAMEMODE"; exit 1 ;;
esac

SRV_DIR="$SRV_BASE/$MC_GAMEMODE"
SRV_JAR="$SRV_DIR/server.jar"
[[ -f "$SRV_JAR" ]] && { echo "Error: no server JAR found in $SRV_DIR"; exit 1; }

ARGS_FILE="$SRV_DIR/jvm.args"

id "$MC_USER" &>/dev/null || { echo "Error: user '$MC_USER' does not exist."; exit 1; }

echo "Starting Minecraft server manually…"
echo "Gamemode  : $MC_GAMEMODE"
echo "Directory : $SRV_DIR"
echo "Jar       : $(basename "$SRV_JAR")"
if [[ -f "$ARGS_FILE" ]]; then
  echo "Args file : $(basename "$ARGS_FILE")"
else
  echo "Args file : (none – using default JVM flags)"
fi

cd "$SRV_DIR"
if [[ -f "$ARGS_FILE" ]]; then
  exec sudo -u "$MC_USER" java @"$ARGS_FILE" -jar "$SRV_JAR" nogui
else
  exec sudo -u "$MC_USER" java -jar "$SRV_JAR" nogui
fi
