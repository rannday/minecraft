#!/usr/bin/env bash
set -euo pipefail
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && { echo "Run, do not source." >&2; exit 1; }
BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$BASE_DIR/lib/log.sh"
trap 'warn "Interrupted. Exiting."; exit 1' INT TERM

source "$BASE_DIR/lib/apt_check.sh"
apt_requirements_check

source "$BASE_DIR/lib/java.sh"

################################################################################
# Install Java
################################################################################
install_temurin() {
  local TEMURIN_JAVA_BIN_PATH="/usr/lib/jvm/temurin-${REQUIRED_JAVA_VERSION}-jdk-${SYS_ARCH}/bin"
  local DESIRED_JAVA="${TEMURIN_JAVA_BIN_PATH}/java"
  local jdk_pkg="temurin-${REQUIRED_JAVA_VERSION}-jdk"

  info "Installing Temurin Java $REQUIRED_JAVA_VERSION …"

  if [[ -x "$DESIRED_JAVA" ]]; then
    register_java_alternatives "${TEMURIN_JAVA_BIN_PATH}"
    ensure_java || fatal "Temurin Java ${REQUIRED_JAVA_VERSION} failed to activate"
    info "Temurin Java ${REQUIRED_JAVA_VERSION} is now active."
    return 0
  fi

  require_packages_apt curl gnupg
  local codename repo_file
  codename="$(. /etc/os-release; echo "$VERSION_CODENAME")"
  repo_file="/etc/apt/sources.list.d/adoptium.list"

  if [[ ! -f /usr/share/keyrings/adoptium.gpg ]]; then
    curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
      | gpg --dearmor | sudo tee /usr/share/keyrings/adoptium.gpg >/dev/null
  fi

  if ! grep -q "packages.adoptium.net" "$repo_file" 2>/dev/null; then
    echo "deb [arch=${SYS_ARCH} signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $codename main" \
      | sudo tee "$repo_file" >/dev/null
  fi

  if ! dpkg -s "$jdk_pkg" >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y "$jdk_pkg"
  fi

  [[ -x "$DESIRED_JAVA" ]] || fatal "Expected Java binary not found at ${DESIRED_JAVA}"
  register_java_alternatives "${TEMURIN_JAVA_BIN_PATH}"

  ensure_java || fatal "Temurin Java ${REQUIRED_JAVA_VERSION} failed to activate"
  info "Temurin Java ${REQUIRED_JAVA_VERSION} is now active."
  return 0
}

install_oracle() {
  warn "Not implemented yet"
  return 1
}

install_openjdk() {
  warn "Not implemented yet"
  return 1
}

uninstall_java() {
  warn "Not implemented yet"
  return 1
}

################################################################################
# CLI Parsing
print_usage() {
  cat <<EOF
Install Java
------------
Usage: ./$(basename "$0") <version>

Commands:
  temurin       Install Temurin Java ${REQUIRED_JAVA_VERSION}
  oracle        Install Oracle Java ${REQUIRED_JAVA_VERSION}
  openjdk       Install OpenJDK ${REQUIRED_JAVA_VERSION}
  uninstall     Uninstall the active Java version
  -h, --help
EOF
}

[[ $# -lt 1 ]] && { print_usage; exit 1; }

COMMAND="$1"
shift

case "$COMMAND" in
  temurin)   install_temurin "$@" ;;
  oracle)    install_oracle "$@" ;;
  openjdk)   install_openjdk "$@" ;;
  uninstall) uninstall_java "$@" ;;
  -h|--help)
    print_usage
    exit 0
    ;;
  *)
    error "Unknown command: $COMMAND"
    echo
    print_usage
    exit 1
    ;;
esac

exit 0