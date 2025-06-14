#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Interrupted. Exiting."; exit 1' INT TERM
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && {
  echo "This script should be executed, not sourced."
  return 1
}

SERVICE_NAME="minecraft"
SESSION_NAME="mcserver"
MC_USER="minecraft"
SERVER_DIR="/opt/minecraft/server/vanilla"
JAR="server.jar"
JVM_ARGS="@jvm.args"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo "Creating or overwriting systemd service: $SERVICE_FILE"
echo "You will be prompted for sudo access if required."

sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Minecraft Vanilla Server (tmux-wrapped)
After=network.target

[Service]
Type=forking
User=$MC_USER
WorkingDirectory=$SERVER_DIR
ExecStart=/usr/bin/tmux new-session -s $SESSION_NAME -d 'java $JVM_ARGS -jar $JAR nogui'
ExecStop=/usr/bin/tmux send-keys -t $SESSION_NAME "stop" C-m
ExecStopPost=/usr/bin/tmux kill-session -t $SESSION_NAME
Restart=on-failure
SuccessExitStatus=0 1
TimeoutStopSec=30
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

echo
echo "Service installed and started."
echo "To attach to the console:   sudo -u $MC_USER tmux attach -t $SESSION_NAME"
echo "To stop the server:         sudo systemctl stop $SERVICE_NAME"
echo "To start the server:        sudo systemctl start $SERVICE_NAME"
