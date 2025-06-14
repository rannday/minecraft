#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Interrupted. Exiting."; exit 1' INT TERM
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && {
  echo "This script should be executed, not sourced."
  return 1
}

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/src" && pwd)"

REQUIRED_SCRIPTS=(setup uninstall install-runtime install-java download run-once)
for name in "${REQUIRED_SCRIPTS[@]}"; do
  [[ -x "${SRC}/${name}.sh" ]] || {
    echo "Missing or non-executable: ${SRC}/${name}.sh"
    exit 1
  }
done

usage() {
  cat <<EOF
Usage: $0 <command> [args...]

Commands:
  --setup, -s         Run setup script (passes args to setup.sh)
  --uninstall, -u     Uninstall a server (passes args to uninstall.sh)
  --runtime, -r       Install systemd + tmux service (install-runtime.sh)
  --java, -j          Install required Java runtime (install-java.sh)
  --download, -d      Fetch latest Minecraft server JAR (download.sh)
  --once, -o          Run one-off setup tasks (run-once.sh)
  -h, --help          Show this help (or -s -h, -u -h, etc)
EOF
  exit 1
}

[[ $# -ge 1 ]] || usage

COMMAND="$1"
shift

case "$COMMAND" in
  --setup|-s)         exec "$SRC/setup.sh" "$@" ;;
  --uninstall|-u)     exec "$SRC/uninstall.sh" "$@" ;;
  --runtime|-r)       exec "$SRC/runtime.sh" "$@" ;;
  --java|-j)          exec "$SRC/java.sh" "$@" ;;
  --download|-d)      exec "$SRC/download.sh" "$@" ;;
  --once|-o)          exec "$SRC/run-once.sh" "$@" ;;
  -h|--help)          usage ;;
  *) echo "Unknown command: $COMMAND"; usage ;;
esac
