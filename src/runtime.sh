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

SRV_DIR="$SRV_BASE/$MC_NAME"
SHUTDOWN_SCRIPT="$SRV_DIR/mc-shutdown.sh"
INSTANCE_UNIT="minecraft@${MC_NAME}.service"
REBOOT_TIMER="minecraft-reboot@${MC_NAME}.timer"
SYSTEMD_DIR="/etc/systemd/system"
TEMPLATE_UNIT="$SYSTEMD_DIR/minecraft@.service"
TEMPLATE_TIMER="$SYSTEMD_DIR/minecraft-reboot@.timer"

[[ -d $SRV_DIR ]] || { echo "[error] No such server dir: $SRV_DIR"; exit 1; }
command -v java >/dev/null || { echo "[error] java not found"; exit 1; }

if [[ ! -f "$TEMPLATE_UNIT" ]]; then
  echo "[init] Writing template: $TEMPLATE_UNIT"
  sudo tee "$TEMPLATE_UNIT" >/dev/null <<EOF
[Unit]
Description=Minecraft server – %%i
After=network.target

[Service]
Type=forking
User=$MC_USER
WorkingDirectory=$SRV_BASE/%%i
ProtectSystem=full
ProtectHome=true
NoNewPrivileges=true

ExecStart=/usr/bin/tmux new-session -s mc-%%i -d /bin/bash -c '\
  cd "'"$SRV_BASE"'/%%i" && \
  if [[ -f jvm.args ]]; then \
    exec /usr/bin/java @jvm.args -jar server.jar nogui; \
  else \
    exec /usr/bin/java -jar server.jar nogui; \
  fi'

ExecStop=${SRV_BASE}/%%i/mc-shutdown.sh mc-%%i
ExecStopPost=/usr/bin/tmux kill-session -t mc-%%i

Restart=on-failure
RestartSec=5
SuccessExitStatus=0 1 143
TimeoutStopSec=45
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
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

sudo tee "$SHUTDOWN_SCRIPT" >/dev/null <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
SESSION=$1
tmux has-session -t "$SESSION" 2>/dev/null || exit 0
tmux send-keys -t "$SESSION" "say Server shutting down in 15 seconds..." C-m
sleep 15
tmux send-keys -t "$SESSION" "save-all" C-m
tmux send-keys -t "$SESSION" "stop" C-m
EOS
sudo chmod +x "$SHUTDOWN_SCRIPT"

sudo systemctl daemon-reexec
sudo systemctl daemon-reload

if $START_INSTANCE; then
  sudo systemctl enable --now "$INSTANCE_UNIT"
  sudo systemctl enable --now "$REBOOT_TIMER"

  echo -e "\nInstance \"$MC_NAME\" is ready:"
  echo "   • Service : sudo systemctl status $INSTANCE_UNIT"
  echo "   • Timer   : systemctl list-timers | grep $MC_NAME"
  echo "   • Console : sudo -u $MC_USER tmux attach -t mc-$MC_NAME"
else
  echo -e "\nTemplates and shutdown script generated for \"$MC_NAME\""
  echo "   • To start: sudo systemctl enable --now $INSTANCE_UNIT"
  echo "   • To check: sudo systemctl status $INSTANCE_UNIT"
fi
