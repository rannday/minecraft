#!/usr/bin/env bash
# --------------------------------------------------------------------------------
# Java Minecraft Server Manager
# --------------------------------------------------------------------------------

set -euo pipefail
trap 'echo "Interrupted. Exiting."; exit 1' INT TERM
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && { echo "Run, don’t source."; return 1; }

# === Real physical path (symlinks resolved) ===
# Gets the real, absolute path to this script, even if it was run via a symlink
# This is the actual directory on disk where the script lives
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# === Invocation path (symlinks NOT resolved) ===
# This is the path the script was called from (could be a symlink)
ALT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --------------------------------------------------------------------------------
# Variables
SCRIPT_VERSION=0.1
# --------------------------------------------------------------------------------

# --------------------------------------------------------------------------------
# Colored Output Functions
# --------------------------------------------------------------------------------
# shellcheck disable=SC2317
info()  { echo -e "\e[32m[INFO]\e[0m $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*"; }
fatal() { echo -e "\e[31m[FATAL]\e[0m $*" >&2; exit 1; }

# --------------------------------------------------------------------------------
# Install function
# --------------------------------------------------------------------------------
install() {
  warn "Not yet implemented: install"
  exit 1
}
# End Install function
# --------------------------------------------------------------------------------


# --------------------------------------------------------------------------------
# Uninstall function
# --------------------------------------------------------------------------------
uninstall() {
  warn "Not yet implemented: uninstall"
  exit 1
}
# End Uninstall function
# --------------------------------------------------------------------------------

# --------------------------------------------------------------------------------
# Setup function
# --------------------------------------------------------------------------------
setup() {
  warn "Not yet implemented: setup"
  exit 1
}
# End Setup function
# --------------------------------------------------------------------------------

# --------------------------------------------------------------------------------
# Run function
# --------------------------------------------------------------------------------
run() {
  warn "Not yet implemented: run"
  exit 1
}
# End Run function
# --------------------------------------------------------------------------------

# --------------------------------------------------------------------------------
# Download function
# --------------------------------------------------------------------------------
download() {
  warn "Not yet implemented: download"
  exit 1
}
# End Download function
# --------------------------------------------------------------------------------

# --------------------------------------------------------------------------------
# CLI Parsing
# --------------------------------------------------------------------------------

print_usage() {
  cat <<EOF
Java Edition Minecraft Server Manager
-------------------------------------
Usage: $(basename "$0") <command> [args...]

Commands:
  install,    Install Java or Minecraft
  uninstall,  Uninstall Java or Minecraft
  setup,      Setup a Minecraft server
  run,        Run a Minecraft server
  download,   Download the latest Minecraft server JAR
  version,    Show the current version of the script
  help,       Can show sub-help menus (e.g. --setup --help)
EOF
}

[[ $# -ge 1 ]] || { print_usage; exit 1; }
COMMAND="$1"
shift

case "$COMMAND" in
  install)    install "$@" ;;
  uninstall)  uninstall "$@" ;;
  setup)      setup "$@" ;;
  run)        run "$@" ;;
  download)   download "$@" ;;
  version|-version|--version|-v)
              info "Java Minecraft Manager v${SCRIPT_VERSION}"; exit 0 ;;
  help|-help|--help|-h)
              print_usage; exit 0 ;;
  *)          error "Unknown command: $COMMAND"; echo; print_usage; exit 1 ;;
esac