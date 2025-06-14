#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Interrupted. Exiting."; exit 1' INT TERM
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && {
  echo "This script should be executed, not sourced."
  return 1
}

usage() {
  cat <<EOF
Usage: ./uninstall.sh [options]

Options:
  --help, -h           Show this help and exit
  <server_type>        Required: survival | creative | adventure
EOF
  exit 1
}

[[ $# -eq 1 ]] || usage

TYPE="$1"
case "$TYPE" in
  survival|creative|adventure) ;;
  *) echo "Invalid server_type: $TYPE"; usage ;;
esac

MC_ROOT="/opt/minecraft"
SRV_DIR="${MC_ROOT}/server/${TYPE}"
SERVICE_NAME="mc-${TYPE}"
TMUX_SESSION="$SERVICE_NAME"

echo "Uninstalling server type: ${TYPE}"
echo "Service: ${SERVICE_NAME}"
echo "Tmux session: ${TMUX_SESSION}"

# Stop with player notice and wait for shutdown
if command -v tmux >/dev/null && sudo -u minecraft tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  sudo -u minecraft tmux send-keys -t "$TMUX_SESSION" "say Server is shutting down in 10 seconds" C-m
  sleep 10
  sudo -u minecraft tmux send-keys -t "$TMUX_SESSION" "stop" C-m

  for i in {1..30}; do
    if ! sudo -u minecraft tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
      echo "Tmux session ${TMUX_SESSION} stopped."
      break
    fi
    sleep 1
  done

  # Final kill if still lingering
  if sudo -u minecraft tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "-- Forcing kill of lingering tmux session."
    sudo -u minecraft tmux kill-session -t "$TMUX_SESSION" || true
  fi
fi

# Stop and remove systemd unit
if systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
  systemctl is-active --quiet "$SERVICE_NAME" && sudo systemctl stop "$SERVICE_NAME"
  sudo systemctl disable --now "$SERVICE_NAME" || true
  sudo rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
  sudo systemctl daemon-reload
  sudo systemctl reset-failed
fi

# Remove server directory
[[ -d "$SRV_DIR" ]] && sudo rm -rf "$SRV_DIR"

# Clean up parent dir if empty
if [[ -d "${MC_ROOT}/server" ]] && [[ -z "$(ls -A "${MC_ROOT}/server")" ]]; then
  sudo rmdir "${MC_ROOT}/server"
fi

echo "Done uninstalling ${TYPE} server."