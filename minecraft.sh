#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Interrupted. Exiting."; exit 1' INT TERM
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && {
  echo "This script should be executed, not sourced."
  return 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${SCRIPT_DIR}/scripts"

REQUIRED_SCRIPTS=(setup uninstall install-runtime install-java download run-once)
for name in "${REQUIRED_SCRIPTS[@]}"; do
  [[ -x "${SCRIPTS}/${name}.sh" ]] || {
    echo "Missing or non-executable: ${SCRIPTS}/${name}.sh"
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
  --setup|-s)         exec "$SCRIPTS/setup.sh" "$@" ;;
  --uninstall|-u)     exec "$SCRIPTS/uninstall.sh" "$@" ;;
  --runtime|-r)       exec "$SCRIPTS/install-runtime.sh" "$@" ;;
  --java|-j)          exec "$SCRIPTS/install-java.sh" "$@" ;;
  --download|-d)      exec "$SCRIPTS/download.sh" "$@" ;;
  --once|-o)          exec "$SCRIPTS/run-once.sh" "$@" ;;
  -h|--help)          usage ;;
  *) echo "Unknown command: $COMMAND"; usage ;;
esac
