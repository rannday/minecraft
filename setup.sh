#!/bin/bash

set -e
trap 'echo "Setup interrupted. Exiting."; exit 1' INT TERM

sudo apt update
sudo apt upgrade -y

sudo apt install -y curl wget gnupg software-properties-common tmux jq git

#if [ ! -f /usr/share/keyrings/adoptium.gpg ]; then
#  echo "Adding Adoptium GPG key..."
#  wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | sudo tee /usr/share/keyrings/adoptium.gpg > /dev/null
#else
#  echo "Adoptium GPG key already present."
#fi
#
#if [ ! -f /etc/apt/sources.list.d/adoptium.list ]; then
#  echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb bookworm main" | sudo tee /etc/apt/sources.list.d/adoptium.list
#fi

# Set up GraalVM key and repository
if [ ! -f /etc/apt/keyrings/graalvm.gpg ]; then
  echo "Adding GraalVM GPG key..."
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://packages.graalvm.org/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/graalvm.gpg > /dev/null
else
  echo "GraalVM GPG key already present."
fi

if [ ! -f /etc/apt/sources.list.d/graalvm.list ]; then
  echo "Adding GraalVM APT repository..."
  echo "deb [signed-by=/etc/apt/keyrings/graalvm.gpg] https://packages.graalvm.org/deb stable main" | sudo tee /etc/apt/sources.list.d/graalvm.list
fi

sudo apt update
#sudo apt install -y temurin-21-jdk
sudo apt install -y graalvm-community-jdk-21

GRAALVM_PATH="/usr/lib/jvm/graalvm-community-openjdk-21"

if [ ! -d "$GRAALVM_PATH" ]; then
  echo "Error: GraalVM install directory not found at $GRAALVM_PATH"
  exit 1
fi

# Check if current java is GraalVM
if java -version 2>&1 | grep -q "GraalVM"; then
  echo "GraalVM is already the default Java."
elif "$GRAALVM_PATH/bin/java" -version 2>&1 | grep -q "GraalVM"; then
  echo "GraalVM installed but not set — applying update-alternatives..."
 
  sudo update-alternatives --install /usr/bin/java java "$GRAALVM_PATH/bin/java" 100
  sudo update-alternatives --install /usr/bin/javac javac "$GRAALVM_PATH/bin/javac" 100

  sudo update-alternatives --set java "$GRAALVM_PATH/bin/java"
  sudo update-alternatives --set javac "$GRAALVM_PATH/bin/javac"
else
  echo "Warning: GraalVM does not appear to be installed correctly."
  exit 1
fi

if ! id minecraft &>/dev/null; then
  echo "Creating 'minecraft' system user..."
  sudo adduser --system --home /opt/minecraft --shell /bin/bash --group minecraft
else
  echo "'minecraft' user already exists."
fi

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
