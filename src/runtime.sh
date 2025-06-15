#!/usr/bin/env bash
# shellcheck disable=SC2154
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
  --name,   -n NAME   Instance name (default: \$MC_NAME from env.sh)
  --user,   -u USER   User to run the service as (default: \$MC_USER)
  --start             Enable and start the instance immediately
  --help,   -h
EOF
}

START_INSTANCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name|-n)   MC_NAME="$2"; shift 2 ;;
    --user|-u)   MC_USER="$2"; shift 2 ;;
    --start)     START_INSTANCE=true; shift ;;
    --help|-h)   print_usage; exit 0 ;;
    *) echo "Unknown option: $1"; print_usage; exit 1 ;;
  esac
done

command -v java >/dev/null || { echo "Error: java not found"; exit 1; }

SRV_DIR="$SRV_BASE/$MC_NAME"
[[ -d "$SRV_DIR" ]] || { echo "Error: No such server dir: $SRV_DIR"; exit 1; }

START_SCRIPT="$SRV_DIR/mc-start.sh"
SHUTDOWN_SCRIPT="$SRV_DIR/mc-shutdown.sh"
RESTART_SCRIPT="$SRV_DIR/mc-restart.sh"

SYSTEMD_DIR="/etc/systemd/system"
SERVICE_NAME="minecraft@${MC_NAME}.service"
REBOOT_TIMER_NAME="minecraft-reboot@${MC_NAME}.timer"
TEMPLATE_UNIT="$SYSTEMD_DIR/minecraft@.service"
TEMPLATE_TIMER="$SYSTEMD_DIR/minecraft-reboot@.timer"

if [[ ! -f "$TEMPLATE_UNIT" ]]; then
  echo "Writing template: $TEMPLATE_UNIT"
  sudo tee "$TEMPLATE_UNIT" >/dev/null <<EOF
[Unit]
Description=Minecraft server - %%i
After=network.target

[Service]
Type=forking
User=$MC_USER
Group=$MC_USER
NoNewPrivileges=true
WorkingDirectory=%h/server/%i
ExecStartPre=%h/server/%i/mc-restart.sh
ExecStart=/usr/bin/env tmux -L $MC_USER new-session -s mc-%i -d /usr/bin/env bash %h/server/%i/mc-start.sh
ExecStop=%h/server/%i/mc-shutdown.sh mc-%i
ExecStopPost=/usr/bin/env tmux -L $MC_USER kill-session -t mc-%i || true
ExecReload=/usr/bin/env tmux -L $MC_USER send-keys -t mc-%i "reload" C-m
Restart=on-failure
RestartSec=5
SuccessExitStatus=0 1 143
TimeoutStopSec=45
RemainAfterExit=true
EOF
fi

if [[ ! -f "$TEMPLATE_TIMER" ]]; then
  echo "[init] Writing template timer: $TEMPLATE_TIMER"
  sudo tee "$TEMPLATE_TIMER" >/dev/null <<EOF
[Unit]
Description=Auto-restart Minecraft %%i daily at 05:00
After=network.target time-sync.target

[Timer]
OnCalendar=*-*-* 05:00:00
Persistent=true
Unit=minecraft@%%i.service

[Install]
WantedBy=timers.target
EOF
fi

sudo tee "$START_SCRIPT" >/dev/null <<EOS
#!/usr/bin/env bash
set -euo pipefail

INSTANCE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$INSTANCE_DIR"

if [[ -f jvm.args ]]; then
  exec /usr/bin/java @jvm.args -jar server.jar nogui
else
  exec /usr/bin/java -jar server.jar nogui
fi
EOS
sudo chmod +x "$START_SCRIPT"

sudo tee "$SHUTDOWN_SCRIPT" >/dev/null <<EOS
#!/usr/bin/env bash
set -euo pipefail
SESSION="mc-$MC_NAME"
tmux -L "$MC_USER" has-session -t "$SESSION" 2>/dev/null || exit 0
tmux -L "$MC_USER" send-keys -t "$SESSION" "say Server shutting down in 15 seconds..." C-m
sleep 15
tmux -L "$MC_USER" send-keys -t "$SESSION" "save-all" C-m
tmux -L "$MC_USER" send-keys -t "$SESSION" "stop" C-m
while tmux -L "$MC_USER" has-session -t "$SESSION" 2>/dev/null; do
  sleep 1
done
EOS
sudo chmod +x "$SHUTDOWN_SCRIPT"

sudo tee "$RESTART_SCRIPT" >/dev/null <<EOS
#!/usr/bin/env bash
set -euo pipefail
SESSION="mc-$MC_NAME"
tmux -L "$MC_USER" has-session -t "$SESSION" 2>/dev/null || exit 0
tmux -L "$MC_USER" send-keys -t "$SESSION" "say Server restarting in 15 seconds..." C-m
sleep 15
tmux -L "$MC_USER" send-keys -t "$SESSION" "save-all" C-m
tmux -L "$MC_USER" send-keys -t "$SESSION" "stop" C-m
while tmux -L "$MC_USER" has-session -t "$SESSION" 2>/dev/null; do
  sleep 1
done
EOS

sudo chmod +x "$RESTART_SCRIPT"

sudo systemctl daemon-reexec
sudo systemctl daemon-reload

if $START_INSTANCE; then
  sudo systemctl enable --now "$SERVICE_NAME"
  sudo systemctl enable --now "$REBOOT_TIMER_NAME"

  echo -e "\nInstance \"$MC_NAME\" is ready:"
  echo "   • Service : sudo systemctl status $SERVICE_NAME"
  echo "   • Timer   : systemctl list-timers | grep $MC_NAME"
  echo "   • Console : sudo -u $MC_USER tmux attach -t mc-$MC_NAME"
else
  echo -e "\nTemplates and shutdown script generated for \"$MC_NAME\""
  echo "   • To start: sudo systemctl enable --now $SERVICE_NAME"
  echo "   • To check: sudo systemctl status $SERVICE_NAME"
fi
