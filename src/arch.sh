#!/usr/bin/env bash
set -euo pipefail
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source, don't run."; exit 1; }
# Detect system architecture
detect_arch() {
  # Normalise $(uname -m) for Temurin compatibility
  case "$(uname -m)" in
    x86_64|amd64)   printf '%s\n' 'amd64'  ;;
    aarch64|arm64)  printf '%s\n' 'arm64'  ;;
    armv7l|armv6l)  printf '%s\n' 'armhf'  ;;
    ppc64le)        printf '%s\n' 'ppc64el' ;;
    s390x)          printf '%s\n' 's390x'  ;;
    *)              printf '%s\n' "$(uname -m)" ;;
  esac
}