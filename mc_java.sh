#!/usr/bin/env bash
set -euo pipefail
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && { echo "Run, do not source." >&2; exit 1; }
BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$BASE_DIR/lib/log.sh"
trap 'warn "Interrupted. Exiting."; exit 1' INT TERM

source "$BASE_DIR/lib/apt.sh"
apt_requirements_check

source "$BASE_DIR/lib/java.sh"

####################################################################################
# Uninstall the active Java version
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