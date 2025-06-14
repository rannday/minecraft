#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Interrupted. Exiting."; exit 1' INT TERM
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && {
  echo "This script should be executed, not sourced."
  return 1
}

SERVER_DIR="/opt/minecraft/server/vanilla"
JAR="$SERVER_DIR/server.jar"
ARGS_FILE="$SERVER_DIR/jvm.args"

if ! id minecraft &>/dev/null; then
  echo "Error: 'minecraft' user does not exist."
  exit 1
fi

if [ ! -f "$JAR" ]; then
  echo "Error: server.jar not found at $JAR"
  exit 1
fi

if [ -f "$ARGS_FILE" ]; then
  echo "Using JVM args from $ARGS_FILE:"
  cat "$ARGS_FILE"
else
  echo "Warning: No jvm.args file found — using default JVM settings."
fi

echo "Starting Minecraft server manually..."
echo "Directory: $SERVER_DIR"
echo "Command: java @$ARGS_FILE -jar server.jar nogui"

sudo -u minecraft bash -c "cd \"$SERVER_DIR\" && exec java @$ARGS_FILE -jar server.jar nogui"