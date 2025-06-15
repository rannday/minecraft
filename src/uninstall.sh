#!/usr/bin/env bash
# shellcheck source=src/env.sh
set -euo pipefail
trap 'echo "Interrupted. Exiting."; exit 1' INT TERM
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && { echo "Run, don’t source."; return 1; }

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SRC_DIR/env.sh"

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [--mode MODE]

Options:
  --mode, -m MODE   Server mode to uninstall (default: \$MC_GAMEMODE)
  --help, -h       
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode|-m) MODE="$2"; shift ;;
    --help|-h) print_usage; exit 0 ;;
    *) echo "Unknown option: $1"; print_usage; exit 1 ;;
  esac
  shift
done

# Use default if not explicitly passed
MODE="${MODE:-$MC_GAMEMODE}"

case "$MODE" in
  survival|creative|adventure) ;;
  *) echo "Invalid mode: $MODE"; print_usage; exit 1 ;;
esac

MC_GAMEMODE="$MODE"

SERVICE_NAME="mc-${MC_GAMEMODE}"
SERVICE="${SERVICE_NAME}.service"
REBOOT_TIMER="${SERVICE_NAME}-reboot.timer"
REBOOT_SERVICE="${SERVICE_NAME}-reboot.service"
TMUX_SESSION="$SERVICE_NAME"
SRV_DIR="${SRV_BASE}/${MC_GAMEMODE}"

echo "Uninstalling Minecraft server for mode: $MC_GAMEMODE"
echo "Service       : $SERVICE"
echo "Reboot timer  : $REBOOT_TIMER"
echo "Tmux session  : $TMUX_SESSION"
echo "Server dir    : $SRV_DIR"
echo

for UNIT in "$REBOOT_TIMER" "$SERVICE"; do
  if systemctl list-unit-files --quiet "$UNIT"; then
    echo "Disabling $UNIT"
    sudo systemctl disable --now "$UNIT" || true
  fi
done
sudo rm -f "/etc/systemd/system/$SERVICE" \
           "/etc/systemd/system/$REBOOT_TIMER" \
           "/etc/systemd/system/$REBOOT_SERVICE"

sudo systemctl daemon-reload
sudo systemctl reset-failed

if sudo -u "$MC_USER" tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  echo "Force-killing lingering tmux session"
  sudo -u "$MC_USER" tmux kill-session -t "$TMUX_SESSION"
fi

if [[ -d "$SRV_DIR" ]]; then
  echo "Removing $SRV_DIR"
  sudo rm -rf "$SRV_DIR"
fi