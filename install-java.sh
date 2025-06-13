#!/bin/bash

set -e
trap 'echo "Setup interrupted. Exiting."; exit 1' INT TERM

REQUIRED_JAVA_VERSION="21"
JAVA_BIN_PATH="/usr/lib/jvm/temurin-${REQUIRED_JAVA_VERSION}-jdk-amd64/bin"

echo "Installing prerequisites..."
sudo apt update
sudo apt install -y wget gnupg software-properties-common

if [ ! -f /usr/share/keyrings/adoptium.gpg ]; then
  wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | gpg --dearmor | sudo tee /usr/share/keyrings/adoptium.gpg > /dev/null
fi

if [ ! -f /etc/apt/sources.list.d/adoptium.list ]; then
  echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb bookworm main" \
    | sudo tee /etc/apt/sources.list.d/adoptium.list
fi

sudo apt update
sudo apt install -y temurin-${REQUIRED_JAVA_VERSION}-jdk

JAVA_VERSION_OUTPUT=$(java -version 2>&1)

if echo "$JAVA_VERSION_OUTPUT" | grep -q "version \"${REQUIRED_JAVA_VERSION}"; then
  echo "Java ${REQUIRED_JAVA_VERSION} is active."
else
  echo "Setting Java ${REQUIRED_JAVA_VERSION} as default..."

  sudo update-alternatives --install /usr/bin/java java "${JAVA_BIN_PATH}/java" 100
  sudo update-alternatives --install /usr/bin/javac javac "${JAVA_BIN_PATH}/javac" 100

  sudo update-alternatives --set java "${JAVA_BIN_PATH}/java"
  sudo update-alternatives --set javac "${JAVA_BIN_PATH}/javac"

  java -version | grep "version \"${REQUIRED_JAVA_VERSION}\"" || {
    echo "Failed to activate Java ${REQUIRED_JAVA_VERSION}."
    exit 1
  }
fi
