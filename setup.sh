#!/bin/bash

set -e
trap 'echo "Setup interrupted. Exiting."; exit 1' INT TERM

sudo apt update
sudo apt upgrade -y

sudo apt install -y curl tmux jq git

cd "$(dirname "$0")"
if [ -f ./install-java.sh ]; then
  ./install-java.sh
else
  echo "Warning: download.sh not found in $(pwd)"
fi

if ! id minecraft &>/dev/null; then
  echo "Creating 'minecraft' system user..."
  sudo adduser --system --home /opt/minecraft --shell /bin/bash --group minecraft
else
  echo "'minecraft' user already exists."
fi

# Ensure /opt/minecraft exists and has proper ownership
if [ ! -d /opt/minecraft ]; then
  echo "Creating /opt/minecraft..."
  sudo mkdir -p /opt/minecraft
fi

sudo chown -R minecraft:minecraft /opt/minecraft

sudo -u minecraft mkdir -p /opt/minecraft/server/vanilla

cd "$(dirname "$0")"
if [ -f ./download.sh ]; then
  ./download.sh
else
  echo "Warning: download.sh not found in $(pwd)"
fi

eula_file="/opt/minecraft/server/vanilla/eula.txt"
if ! grep -q 'eula=true' "$eula_file" 2>/dev/null; then
  sudo -u minecraft bash -c 'echo "eula=true" > /opt/minecraft/server/vanilla/eula.txt'
fi

jvm_args_file="/opt/minecraft/server/vanilla/jvm.args"

if [ ! -f "$jvm_args_file" ]; then
  echo "Creating default JVM args at $jvm_args_file..."
  sudo -u minecraft tee "$jvm_args_file" > /dev/null <<EOF
-Xmx4G
-Xms4G
-XX:+UseG1GC
-XX:+ParallelRefProcEnabled
-XX:+UnlockExperimentalVMOptions
EOF
else
  echo "JVM args file already exists at $jvm_args_file — skipping."
fi
