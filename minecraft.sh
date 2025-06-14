#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Interrupted. Exiting."; exit 1' INT TERM
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && { echo "Run, don’t source."; return 1; }

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/src" && pwd)"

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
  --setup,     -s  Run setup script (passes args to setup.sh)
  --uninstall, -u  Uninstall a server (passes args to uninstall.sh)
  --runtime,   -r  Install systemd + tmux service (install-runtime.sh)
  --java,      -j  Install required Java runtime (install-java.sh)
  --download,  -d  Fetch latest Minecraft server JAR (download.sh)
  --once,      -o  Run one-off setup tasks (run-once.sh)
  --help,      -h  Show this help (or -s -h, -u -h, etc)
EOF
  exit 0
}

[[ $# -ge 1 ]] || usage

COMMAND="$1"
shift

case "$COMMAND" in
  --setup|-s)         run_script "$SRC/setup.sh" "$@" ;;
  --uninstall|-u)     run_script "$SRC/uninstall.sh" "$@" ;;
  --runtime|-r)       run_script "$SRC/runtime.sh" "$@" ;;
  --java|-j)          run_script "$SRC/java.sh" "$@" ;;
  --download|-d)      run_script "$SRC/download.sh" "$@" ;;
  --once|-o)          run_script "$SRC/run-once.sh" "$@" ;;
  -h|--help)          usage ;;
  *) echo "Unknown command: $COMMAND"; usage ;;
esac
