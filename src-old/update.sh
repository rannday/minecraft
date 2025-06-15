#!/usr/bin/env bash
# shellcheck source=src/env.sh
# shellcheck source=src/utils.sh
set -euo pipefail
trap 'echo "Interrupted. Exiting."; exit 1' INT TERM
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && { echo "Run, don’t source."; return 1; }

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SRC_DIR/env.sh"
source "$SRC_DIR/utils.sh"

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [--mode MODE]

Options:
  --mode, -m MODE   Gamemode directory to update (default: \$MC_GAMEMODE)
  --user, -u USER   Override default MC_USER from env.sh
  --help, -h
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode|-m)
      [[ -n $2 ]] || { echo "Option $1 requires an argument"; print_usage; exit 1; }
      MC_GAMEMODE=$2
      shift 2
      ;;
    --user|-u)
      MC_USER=$2
      shift 2
      ;;
    --help|-h)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      print_usage
      exit 1
      ;;
  esac
done

case "$MC_GAMEMODE" in
  survival|creative|adventure) ;;
  *) echo "Invalid gamemode: $MC_GAMEMODE"; print_usage; exit 1 ;;
esac

SRV_DIR="${SRV_BASE}/${MC_GAMEMODE}"
SERVICE_NAME="mc-${MC_GAMEMODE}"
SYMLINK="${SRV_DIR}/server.jar"

[[ -d "$SRV_DIR" ]] || { echo "Server folder $SRV_DIR not found"; exit 1; }

current_ver=""
if [[ -L "$SYMLINK" ]]; then
  current_ver="$(basename "$(readlink "$SYMLINK")" | sed -E 's/^minecraft_server_([0-9.]+)\.jar$/\1/')"
fi

read -r latest_ver server_url sha1 <<<"$(get_latest_server_meta)"

echo "Current : ${current_ver:-<none>}"
echo "Latest  : $latest_ver"

if [[ "$current_ver" == "$latest_ver" ]]; then
  echo "Already on latest; nothing to do."
  exit 0
fi

new_jar="${SRV_DIR}/minecraft_server_${latest_ver}.jar"
echo "Downloading $latest_ver ..."
sudo curl -fLs -o "$new_jar" "$server_url"

echo "Verifying checksum ..."
actual_sha1="$(sha1sum "$new_jar" | awk '{print $1}')"
[[ "$actual_sha1" == "$sha1" ]] || { echo "SHA1 mismatch"; exit 1; }

echo "Stopping service $SERVICE_NAME (if active) ..."
if systemctl is-active --quiet "$SERVICE_NAME"; then
  sudo systemctl stop "$SERVICE_NAME"
fi

# -------------------
# Rotate symlink
# -------------------
echo "Updating symlink → $(basename "$new_jar")"
sudo ln -sf "$(basename "$new_jar")" "$SYMLINK"

# -------------------
# Restart service if it was active
# -------------------
echo "Starting service $SERVICE_NAME ..."
sudo systemctl start "$SERVICE_NAME"

echo "Update complete"