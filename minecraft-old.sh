#!/usr/bin/env bash
# shellcheck source=src/requirements.sh
set -euo pipefail
trap 'echo "Interrupted. Exiting."; exit 1' INT TERM
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && { echo "Run, don’t source."; return 1; }

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/src" && pwd)"

source "$SRC_DIR/requirements.sh"

run_script() {
  local script="$1"
  shift
  if [[ ! -x "$script" ]]; then
    echo "Missing or non-executable: $script"
    exit 1
  fi
  exec "$script" "$@"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [args...]

Commands:
  setup,      Run setup script (passes args to setup.sh)
  update,     Update the server (passes args to update.sh)
  uninstall   Uninstall a server (passes args to uninstall.sh)
  runtime,    Install systemd + tmux service (install-runtime.sh)
  java,       Install required Java runtime (install-java.sh)
  download,   Fetch latest Minecraft server JAR (download.sh)
  once,       Run one-off setup tasks (run-once.sh)
  help,       Can show sub-help menus (e.g. --setup --help)
EOF
}

[[ $# -ge 1 ]] || usage

COMMAND="$1"
shift

case "$COMMAND" in
  setup)         run_script "$SRC_DIR/setup.sh" "$@" ;;
  update)        run_script "$SRC_DIR/update.sh" "$@" ;;
  uninstall)        run_script "$SRC_DIR/uninstall.sh" "$@" ;;
  runtime)       run_script "$SRC_DIR/runtime.sh" "$@" ;;
  java)          run_script "$SRC_DIR/java.sh" "$@" ;;
  download)      run_script "$SRC_DIR/download.sh" "$@" ;;
  once)          run_script "$SRC_DIR/run-once.sh" "$@" ;;
  help)          usage; exit 0 ;;
  *) echo "Unknown command: $COMMAND"; usage; exit 1 ;;
esac
