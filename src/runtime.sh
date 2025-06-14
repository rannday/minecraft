#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Interrupted. Exiting."; exit 1' INT TERM
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && { echo "Run, don’t source."; return 1; }

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SRC_DIR/env.sh"
source "$SRC_DIR/utils.sh"

SERVICE_NAME="mc-${MC_GAMEMODE}"
SESSION_NAME="$SERVICE_NAME"
SRV_DIR="${SRV_BASE}/${MC_GAMEMODE}"
JAR="${SRV_DIR}/server.jar"
JVM_ARGS_FILE="${SRV_DIR}/jvm.args"
SHUTDOWN_SCRIPT="${SRV_DIR}/mc-shutdown.sh"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
REBOOT_SERVICE="/etc/systemd/system/${SERVICE_NAME}-reboot.service"
REBOOT_TIMER="/etc/systemd/system/${SERVICE_NAME}-reboot.timer"
JAVA="${JAVA_BIN_PATH}/java"

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Creates/overwrites the systemd unit file only (does NOT enable or start it).

Options:
  --mode,     -m MODE  Gamemode to set up   (default: ${MC_GAMEMODE})
  --user,     -u USER  User to run as       (default: ${MC_USER})
  --srv-dir,  -d DIR   Server working dir   (default: ${SRV_DIR})
  --jar,      -j FILE  Path to server JAR   (default: ${JAR})
  --jvm-args, -a FILE  Path to JVM argfile  (default: ${JVM_ARGS_FILE})
  --help,     -h       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode|-m)
      MC_GAMEMODE="$2"
      SERVICE_NAME="mc-${MC_GAMEMODE}"
      SESSION_NAME="$SERVICE_NAME"
      SRV_DIR="${SRV_BASE}/${MC_GAMEMODE}"
      JAR="${SRV_DIR}/server.jar"
      JVM_ARGS_FILE="${SRV_DIR}/jvm.args"
      SHUTDOWN_SCRIPT="${SRV_DIR}/mc-shutdown.sh"
      SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
      shift ;;
    --user|-u)     MC_USER="$2"; shift ;;
       --srv-dir|-d)
      SRV_DIR="$2"
      JAR="${SRV_DIR}/server.jar"
      JVM_ARGS_FILE="${SRV_DIR}/jvm.args"
      SHUTDOWN_SCRIPT="${SRV_DIR}/mc-shutdown.sh"
      SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
      shift ;;
    --jar|-j)      JAR="$2"; shift ;;
    --jvm-args|-a) JVM_ARGS_FILE="$2"; shift ;;
    -h|--help)     print_usage; exit 0 ;;
    *) echo "Unknown option: $1"; print_usage; exit 1 ;;
  esac
  shift
done

require_packages tmux

[[ -d "$SRV_DIR" ]] || {
  echo "[error] Server directory not found: $SRV_DIR" >&2
  exit 1
}

command -v "$JAVA" >/dev/null || {
  echo "[error] Java not found at $JAVA" >&2
  exit 1
}

sudo tee "$SHUTDOWN_SCRIPT" >/dev/null <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
SESSION="$1"
tmux has-session -t "$SESSION" 2>/dev/null || exit 0
tmux send-keys -t "$SESSION" "say Server shutting down in 15 seconds..." C-m
sleep 15
tmux send-keys -t "$SESSION" "save-all" C-m
tmux send-keys -t "$SESSION" "stop" C-m
EOS

sudo chmod +x "$SHUTDOWN_SCRIPT"

echo "[systemd] Writing unit file: $SERVICE_FILE"
sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=Minecraft ${MC_GAMEMODE^} Server
After=network.target

[Service]
Type=forking
User=$MC_USER
WorkingDirectory=$SRV_DIR
ProtectSystem=full
ProtectHome=true
NoNewPrivileges=true

ExecStart=/usr/bin/tmux new-session -s ${SESSION_NAME} -d "${JAVA} @${JVM_ARGS_FILE} -jar ${JAR} nogui"
ExecStop=${SHUTDOWN_SCRIPT} ${SESSION_NAME}
ExecStopPost=/usr/bin/tmux kill-session -t ${SESSION_NAME}

Restart=on-failure
RestartSec=5
SuccessExitStatus=0 1 143
TimeoutStopSec=45
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

echo "[systemd] Writing reboot helper: $REBOOT_SERVICE"
sudo tee "$REBOOT_SERVICE" >/dev/null <<EOF
[Unit]
Description=Daily reboot of ${SERVICE_NAME}.service
Requires=${SERVICE_NAME}.service
After=${SERVICE_NAME}.service

[Service]
Type=oneshot
ExecStart=/bin/systemctl restart ${SERVICE_NAME}.service

[Install]
WantedBy=multi-user.target
EOF

echo "[systemd] Writing reboot timer : $REBOOT_TIMER"
sudo tee "$REBOOT_TIMER" >/dev/null <<EOF
[Unit]
Description=Auto-restart ${MC_GAMEMODE^} server daily at 05:00
After=network.target time-sync.target

[Timer]
OnCalendar=*-*-* 05:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload

cat <<INFO
Unit file created at $SERVICE_FILE ✔

Next steps (manual):
  # Enable and start the service
  sudo systemctl enable --now $SERVICE_NAME

  # Enable and start the reboot timer
  sudo systemctl enable --now ${SERVICE_NAME}-reboot.timer

  # Attach to the console if running
  sudo -u $MC_USER tmux attach -t $SESSION_NAME
  # Check running sessions
  sudo -u $MC_USER tmux ls

INFO
