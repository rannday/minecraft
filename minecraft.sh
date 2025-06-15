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
  --setup,      -s    Run setup script (passes args to setup.sh)
  --update,     -u    Update the server (passes args to update.sh)
  --uninstall         Uninstall a server (passes args to uninstall.sh)
  --runtime,    -r    Install systemd + tmux service (install-runtime.sh)
  --java,       -j    Install required Java runtime (install-java.sh)
  --download,   -d    Fetch latest Minecraft server JAR (download.sh)
  --once,       -o    Run one-off setup tasks (run-once.sh)
  --help,       -h    Can show sub-help menus (e.g. --setup --help)
EOF
}

[[ $# -ge 1 ]] || usage

COMMAND="$1"
shift

case "$COMMAND" in
  --setup|-s)         run_script "$SRC_DIR/setup.sh" "$@" ;;
  --update|-u)        run_script "$SRC_DIR/update.sh" "$@" ;;
  --uninstall)        run_script "$SRC_DIR/uninstall.sh" "$@" ;;
  --runtime|-r)       run_script "$SRC_DIR/runtime.sh" "$@" ;;
  --java|-j)          run_script "$SRC_DIR/java.sh" "$@" ;;
  --download|-d)      run_script "$SRC_DIR/download.sh" "$@" ;;
  --once|-o)          run_script "$SRC_DIR/run-once.sh" "$@" ;;
  -h|--help)          usage; exit 0 ;;
  *) echo "Unknown command: $COMMAND"; usage; exit 1 ;;
esac
