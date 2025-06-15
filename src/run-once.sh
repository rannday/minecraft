#!/usr/bin/env bash
# shellcheck source=src/env.sh
# shellcheck source=src/utils.sh
set -euo pipefail
trap 'echo "Interrupted. Exiting."; exit 1' INT TERM
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && { echo "Run, don’t source."; return 1; }

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SRC_DIR/env.sh"
source "$SRC_DIR/utils.sh"

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --name, -n NAME   Name of the Minecraft server instance (default: \$MC_NAME)
  --user, -u USER   User to run the server as (default: \$MC_USER)
  --help, -h
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name|-n) MC_NAME="$2"; shift 2 ;;
    --user|-u) MC_USER="$2"; shift 2 ;;
    --help|-h)  print_usage;  exit 0 ;;
    *)         echo "Unknown option: $1"; print_usage; exit 1 ;;
  esac
done

command -v java >/dev/null || { echo "Error: java not found"; exit 1; }

SRV_DIR="$SRV_BASE/$MC_NAME"
SRV_JAR="$SRV_DIR/server.jar"
[[ -f "$SRV_JAR" ]] || { echo "Error: server.jar not found in $SRV_DIR"; exit 1; }

ARGS_FILE="$SRV_DIR/jvm.args"

id "$MC_USER" &>/dev/null || { echo "Error: user '$MC_USER' does not exist."; exit 1; }

echo "Starting Minecraft server $MC_NAME manually"
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
