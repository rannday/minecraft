#!/bin/bash

set -e

sudo apt update
sudo apt upgrade -y

sudo apt install -y curl wget gnupg software-properties-common tmux jq git

wget -O - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | sudo tee /usr/share/keyrings/adoptium.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb bookworm main" | sudo tee /etc/apt/sources.list.d/adoptium.list
sudo apt update
sudo apt install temurin-21-jdk

sudo adduser --system --home /opt/minecraft --shell /bin/bash minecraft || true
sudo -u minecraft mkdir -p /opt/minecraft/server/vanilla

./download.sh

sudo -u minecraft bash -c 'echo "eula=true" > /opt/minecraft/server/vanilla/eula.txt'
