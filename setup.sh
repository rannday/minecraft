#!/bin/bash

set -e
trap 'echo "Setup interrupted. Exiting."; exit 1' INT TERM

sudo apt update
sudo apt upgrade -y

sudo apt install -y curl wget gnupg software-properties-common tmux jq git

if [ ! -f /usr/share/keyrings/adoptium.gpg ]; then
  echo "Adding Adoptium GPG key..."
  wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | sudo tee /usr/share/keyrings/adoptium.gpg > /dev/null
else
  echo "Adoptium GPG key already present."
fi

if [ ! -f /etc/apt/sources.list.d/adoptium.list ]; then
  echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb bookworm main" | sudo tee /etc/apt/sources.list.d/adoptium.list
fi

sudo apt update
sudo apt install -y temurin-21-jdk

if ! id minecraft &>/dev/null; then
  echo "Creating 'minecraft' system user..."
  sudo adduser --system --home /opt/minecraft --shell /bin/bash --group minecraft
else
  echo "'minecraft' user already exists."
fi

sudo -u minecraft mkdir -p /opt/minecraft/server/vanilla

cd "$(dirname "$0")"
./download.sh

eula_file="/opt/minecraft/server/vanilla/eula.txt"
if ! grep -q 'eula=true' "$eula_file" 2>/dev/null; then
  sudo -u minecraft bash -c 'echo "eula=true" > /opt/minecraft/server/vanilla/eula.txt'
fi