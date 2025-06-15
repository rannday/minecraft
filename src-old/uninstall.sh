#!/usr/bin/env bash
# shellcheck source=src/env.sh
set -euo pipefail
trap 'echo "Interrupted. Exiting."; exit 1' INT TERM
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && { echo "Run, don’t source."; return 1; }

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SRC_DIR/env.sh"

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [option]

Options:
  --name, -n NAME  Server name to uninstall (default: \$MC_NAME)
  --help, -h       
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name|-n) MC_NAME="$2"; shift 2 ;;
    --help|-h) print_usage; exit 0 ;;
    *) echo "Unknown option: $1"; print_usage; exit 1 ;;
  esac
done

SERVICE_NAME="minecraft@${MC_NAME}.service"
REBOOT_TIMER_NAME="minecraft-reboot@${MC_NAME}.timer"
TMUX_SESSION_NAME="mc-${MC_NAME}"
SRV_DIR="${SRV_BASE}/${MC_NAME}"

echo "Uninstalling Minecraft server - $MC_NAME"
echo "Service       : $SERVICE_NAME"
echo "Reboot timer  : $REBOOT_TIMER_NAME"
echo "Tmux session  : $TMUX_SESSION_NAME"
echo "Server dir    : $SRV_DIR"
echo

sudo systemctl disable --now "$SERVICE_NAME" \
                             "$REBOOT_TIMER_NAME"

sudo systemctl daemon-reload
sudo systemctl reset-failed

if sudo -u "$MC_USER" tmux -L "$MC_USER" has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
  echo "Force-killing lingering tmux session"
  sudo -u "$MC_USER" tmux -L "$MC_USER" kill-session -t "$TMUX_SESSION_NAME"
fi

if [[ -d "$SRV_DIR" ]]; then
  echo "Removing $SRV_DIR"
  sudo rm -rf "$SRV_DIR"
fi

echo "Uninstall complete."
exit 0