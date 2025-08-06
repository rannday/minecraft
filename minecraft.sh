#!/usr/bin/env bash
# Java Minecraft Server Manager
set -euo pipefail
trap 'echo "Interrupted. Exiting."; exit 1' INT TERM
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && { echo "Run, do not source."; return 1; }

readonly SCRIPT_VERSION=0.1

################################################################################
SYS_ARCH="$(case "$(uname -m)" in
  x86_64|amd64)   echo amd64 ;;
  aarch64|arm64)  echo arm64 ;;
  armv7l|armv6l)  echo armhf ;;
  ppc64le)        echo ppc64el ;;
  s390x)          echo s390x ;;
  *)              uname -m ;;
esac)"
readonly SYS_ARCH

################################################################################
REQUIRED_JAVA_VERSION="21"
readonly TEMURIN_JAVA_BIN_PATH="/usr/lib/jvm/temurin-${REQUIRED_JAVA_VERSION}-jdk-${SYS_ARCH}/bin"

################################################################################
# Minecraft server instance configuration
MC_TYPE="minecraft"
MC_NAME="vanilla"
MC_USER="minecraft"
MC_HOME="/srv/minecraft"
MC_BIN="$MC_HOME/bin"
MC_INSTANCES="$MC_HOME/instances"
MC_BACKUPS="$MC_HOME/backups"

################################################################################
# Default Minecraft server settings
MC_MOTD="Minecraft Server"
MC_PORT=25565
MC_RAM="4G"
MC_GAMEMODE="survival"
MC_PVP="false"
MC_WHITELIST=""

# RAM to player ratio
MC_RAM_RATIO=1

# URL for Mojang manifest
readonly MC_VERSION_MANIFEST_URL="https://piston-meta.mojang.com/mc/game/version_manifest.json"

################################################################################
# shellcheck disable=SC2317
info()  { echo -e "\e[32m[INFO]\e[0m $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*"; }
fatal() { echo -e "\e[31m[FATAL]\e[0m $*" >&2; exit 1; }

################################################################################
# Shared functions
ensure_java() {
  local java_bin
  if ! java_bin=$(command -v java 2>/dev/null); then
    warn "No 'java' found in PATH."
    return 1
  fi

  local ver_line
  ver_line=$("$java_bin" -version 2>&1 | head -n1)
  if [[ -z "$ver_line" || "$ver_line" != *version* ]]; then
    warn "'$java_bin' did not return a recognizable version string."
    return 1
  fi

  local ver_major
  if [[ $ver_line =~ \"([0-9]+)\.([0-9]+) ]]; then
    ver_major="${BASH_REMATCH[1]}"
    [[ $ver_major == 1 ]] && ver_major="${BASH_REMATCH[2]}"
  else
    ver_major=$(awk -F\" '{print $2}' <<<"$ver_line" | cut -d. -f1)
  fi

  if [[ "$ver_major" != "$REQUIRED_JAVA_VERSION" ]]; then
    warn "Java found at $java_bin, but version is $ver_major — expected $REQUIRED_JAVA_VERSION."
    return 1
  fi

  info "Java $ver_major found at $java_bin (OK)"
  return 0
}

################################################################################
register_java_alternatives() {
  local bin_dir="$1"
  local java_path="$bin_dir/java"
  local javac_path="$bin_dir/javac"

  [[ -x "$java_path" && -x "$javac_path" ]] || \
    fatal "Expected binaries not found in $bin_dir"

  # Ensure update-alternatives is available
  command -v update-alternatives >/dev/null || fatal "'update-alternatives' not found"

  # Register if needed
  if ! update-alternatives --query java 2>/dev/null | grep -q "Value: $java_path"; then
    info "Registering JDK in $bin_dir via update-alternatives …"
    sudo update-alternatives --install /usr/bin/java  java  "$java_path"  100
    sudo update-alternatives --install /usr/bin/javac javac "$javac_path" 100
  fi

  # Set as default
  sudo update-alternatives --set java  "$java_path"
  sudo update-alternatives --set javac "$javac_path"

  info "JDK in $bin_dir is now the active version."
}

################################################################################
resolve_symlink() {
  local target=$1
  cd "$(dirname "$target")" || return 1
  target=$(basename "$target")

  # Follow symlinks until we reach the real file
  while [ -L "$target" ]; do
    target=$(readlink "$target")
    cd "$(dirname "$target")" || return 1
    target=$(basename "$target")
  done

  # Get the absolute path
  echo "$(pwd -P)/$target"
}

################################################################################
get_latest_server_meta() {
  local manifest_url="$MC_VERSION_MANIFEST_URL"
  local latest_ver
  local meta_url

  latest_ver=$(curl -s "$manifest_url" | jq -r '.latest.release')
  meta_url=$(curl -s "$manifest_url" | \
             jq -r --arg ver "$latest_ver" '.versions[] | select(.id == $ver) | .url')

  if [[ -z "$meta_url" ]]; then
    echo "Error: could not resolve metadata URL for $latest_ver" >&2
    return 1
  fi

  local server_url sha1
  read -r server_url sha1 <<<"$(curl -s "$meta_url" | \
        jq -r '.downloads.server | "\(.url) \(.sha1)"')"

  [[ -n "$server_url" && -n "$sha1" ]] || {
    echo "Error: incomplete server metadata" >&2
    return 1
  }

  echo "$latest_ver $server_url $sha1"
}

################################################################################
require_packages_apt() {
  local do_install=false
  local missing=()
  local pkgs=()

  # Flag parsing
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -i|--install|-install) do_install=true; shift ;;
      --) shift; break ;;
      -*) fatal "Unknown option: $1" ;;
      *)  pkgs+=("$1"); shift ;;
    esac
  done

  # Detect missing packages
  for pkg in "${pkgs[@]}"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
      missing+=("$pkg")
    fi
  done

  # All present
  [[ ${#missing[@]} -eq 0 ]] && return 0

  warn "Missing APT packages: ${missing[*]}"

  # If no --install flag → fail
  if ! $do_install; then
    fatal "Install them manually or re-run with --install."
  fi

  # Abort on non-Debian systems
  [[ -f /etc/debian_version ]] \
    || fatal "Auto-install only supported on Debian/Ubuntu systems."

  info "Installing: ${missing[*]}"
  sudo apt-get update -qq
  sudo apt-get install -y "${missing[@]}"
}
# End shared functions

################################################################################
download() {

  print_download_help() {
    cat <<EOF
Usage: $(basename "$0") download [options]

  -t, --type   TYPE  Type of server to download (default: $MC_TYPE)
                     Supported types: 'minecraft', not implemented - 'atm10' and others
       --url   URL   Custom URL to download from (overrides type) 
  -d, --dest   DIR   Destination directory (default: $MC_INSTANCES/$MC_NAME)
  -u, --user   USER  Run curl as USER (default: $MC_USER)
  -h, --help
EOF
  }

  local TEMP type server_url dest user
  TEMP=$(getopt -o ht:d:u: --long help,type:,url:,dest:,user: -n 'download' -- "$@") || return 1
  eval set -- "$TEMP"

  while true; do
    case "$1" in
      -t|--type)  type="$2";  shift 2 ;; 
      --url)      url="$2";   shift 2 ;;
      -d|--dest)  dest="$2";  shift 2 ;;
      -u|--user)  user="$2";  shift 2 ;;
      -h|--help)
        print_download_help
        return 0 ;;
      --) shift; break ;;
      *)  print_download_help; fatal "Unexpected option $1" ;;
    esac
  done

  # Default fallbacks
  [[ -z "${dest:-}" ]] && dest="${MC_INSTANCES}/${MC_NAME}"
  [[ -z "${user:-}"   ]] && user="${MC_USER}"
  [[ -d "$dest" ]] || fatal "Destination directory '$dest' does not exist."
  id -u "$user" >/dev/null 2>&1 || fatal "User '$user' not found."

  require_packages_apt -i curl jq

  info "Type: $type, Destination: $dest, User: $user"

  # resolve download URL & expected SHA1
  local latest_ver expected_sha1
  if [[ -n "${url:-}" ]]; then
    info "--url provided; skipping type logic."
    latest_ver="custom"
    expected_sha1="SKIP"
  else
    [[ -z "${type:-}" ]] && type="minecraft"

    case "$type" in
      minecraft)
        info "Fetching latest vanilla metadata …"
        read -r latest_ver url expected_sha1 <<<"$(get_latest_server_meta)" || \
          fatal "Failed to retrieve metadata."
        ;;
      *)
        fatal "Server type '$type' is not supported yet."
        ;;
    esac
  fi

  # determine paths
  local jar_name
  if [[ "$latest_ver" == "custom" ]]; then
    jar_name="$(basename "$url")"
  else
    jar_name="minecraft_server_${latest_ver}.jar"
  fi
  local jar_path="${dest}/${jar_name}"

  # helper: verify SHA1
  verify_checksum() {  # $1=file  $2=sha1
    local actual
    actual=$(sha1sum "$1" | awk '{print $1}')
    [[ "$2" == "$actual" ]]
  }

  # existing file check
  if [[ -f "$jar_path" ]]; then
    info "JAR already exists; validating …"
    if [[ "$expected_sha1" == "SKIP" ]] || verify_checksum "$jar_path" "$expected_sha1"; then
      info "Existing file is valid – nothing to do."
      return 0
    else
      warn "Checksum mismatch – re-downloading."
      sudo -u "$user" rm -f "$jar_path"
    fi
  fi

  # download & (optionally) verify
  info "Downloading $(basename "$jar_path") …"
  if ! sudo -u "$user" curl -fLs -o "$jar_path" "$url"; then
    fatal "Download failed from $url"
  fi

  if [[ "$expected_sha1" != "SKIP" ]]; then
    info "Verifying checksum …"
    verify_checksum "$jar_path" "$expected_sha1" || fatal "SHA-1 mismatch after download."
    info "Checksum OK."
  else
    info "Checksum skipped (no SHA-1 available)."
  fi

  info "Download complete: $jar_path"
}
# End Download function

################################################################################
install() {

  print_install_help() {
    cat <<EOF
Usage: $(basename "$0") install [options]

Options:
  --java       Install Temurin Java ${REQUIRED_JAVA_VERSION}
  -h, --help   Show this help message
EOF
  }

  local install_java=false

  # Parse options
  local TEMP
  TEMP=$(getopt -o h --long help,java -n 'install' -- "$@") || exit 1
  eval set -- "$TEMP"

  while true; do
    case "$1" in
      --java) install_java=true; shift ;;
      -h|--help)
        print_install_help
        return 0 ;;
      --) shift; break ;;
      *)  print_install_help; fatal "Unexpected option $1" ;;
    esac
  done

  if "$install_java"; then
    # Ensure Java's installed and return early if so
    if ensure_java; then
      return 0 
    fi

    info "Installing Temurin Java $REQUIRED_JAVA_VERSION …"

    require_packages_apt -i sudo curl gnupg 
    local codename repo_file
    codename="$(. /etc/os-release; echo "$VERSION_CODENAME")"
    repo_file="/etc/apt/sources.list.d/adoptium.list"

    # Key
    if [[ ! -f /usr/share/keyrings/adoptium.gpg ]]; then
      curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
        | gpg --dearmor | sudo tee /usr/share/keyrings/adoptium.gpg >/dev/null
    fi

    # Repo line
    if ! grep -q "packages.adoptium.net" "$repo_file" 2>/dev/null; then
      echo "deb [arch=$SYS_ARCH signed-by=/usr/share/keyrings/adoptium.gpg] \
  https://packages.adoptium.net/artifactory/deb $codename main" \
        | sudo tee "$repo_file" >/dev/null
    fi

    # Check if the java bin path exists
    if [[ -x "${TEMURIN_JAVA_BIN_PATH}/java" ]]; then
      register_java_alternatives "${TEMURIN_JAVA_BIN_PATH}"
    else
      # Install Temurin JDK (unconditionally)
      local jdk_pkg="temurin-${REQUIRED_JAVA_VERSION}-jdk"
      sudo apt-get update -qq
      sudo apt-get install -y "$jdk_pkg"
    fi

    # Try to validate Java install
    if ! ensure_java; then
      # If validation fails, attempt to register manually
      if [[ -x "${TEMURIN_JAVA_BIN_PATH}/java" ]]; then
        register_java_alternatives "${TEMURIN_JAVA_BIN_PATH}"
      else
        fatal "Expected Java binary not found at ${TEMURIN_JAVA_BIN_PATH}/java"
      fi

      # Re-check after manual registration
      ensure_java || fatal "Temurin Java ${REQUIRED_JAVA_VERSION} failed to activate"
    fi

    info "Temurin Java ${REQUIRED_JAVA_VERSION} is now active."
  else
    print_install_help
    return 1
  fi
  exit 0
}
# End Install function

################################################################################
uninstall() {
  warn "Not yet implemented"
  exit 0
}
# End Uninstall function

################################################################################
setup() {

  print_setup_help() {
    cat <<EOF
Usage: $(basename "$0") setup [options]

User
  --user      USER    System user                 (default: $MC_USER)
  --home      DIR     Home dir                    (default: $MC_HOME)

Instance
  --name      NAME    Instance name               (default: $MC_NAME)
  --motd      TEXT    MOTD                        (default: "$MC_MOTD")
  --port      NUM     TCP port                    (default: $MC_PORT)
  --ram       SIZE    Heap (-Xms/-Xmx)            (default: $MC_RAM)
  --gamemode  MODE    survival|creative|adventure (default: $MC_GAMEMODE)
  --pvp       BOOL    true|false                  (default: $MC_PVP)
  --whitelist LIST    Comma-sep player list       (default: disabled)
  --ram-ratio NUM     Players per GiB             (default: $MC_RAM_RATIO)
EOF
  }

  # getopt parser
  local TEMP
  TEMP=$(getopt -o h --long \
    help,name:,user:,home:,motd:,port:,ram:,gamemode:,pvp:,whitelist:,ram-ratio: \
    -n 'setup' -- "$@") || exit 1
  eval set -- "$TEMP"

  while true; do
    case "$1" in
      --name)        MC_NAME="$2";       shift 2 ;;
      --user)        MC_USER="$2";       shift 2 ;;
      --home)        MC_HOME="$2";       shift 2 ;;
      --motd)        MC_MOTD="$2";       shift 2 ;;
      --port)        MC_PORT="$2";       shift 2 ;;
      --ram)         MC_RAM="$2";        shift 2 ;;
      --gamemode)    MC_GAMEMODE="$2";   shift 2 ;;
      --pvp)         MC_PVP="$2";        shift 2 ;;
      --whitelist)   MC_WHITELIST="$2";  shift 2 ;;
      --ram-ratio)   MC_RAM_RATIO="$2";  shift 2 ;;
      -h|--help)
        print_setup_help
        exit 0 ;;
      --) shift; break ;;
      *)  
        print_setup_help
        fatal "Unexpected option $1" ;;
    esac
  done

  ##############################################################################
  # Gamemode check
  [[ "$MC_GAMEMODE" =~ ^(survival|creative|adventure)$ ]] \
    || fatal "Invalid --gamemode '$MC_GAMEMODE'"

  ##############################################################################
  # Port check
  if ! [[ "$MC_PORT" =~ ^[0-9]+$ ]] || (( MC_PORT < 1024 || MC_PORT > 65535 )); then
    fatal "Invalid --port '$MC_PORT'. Must be a number between 1024–65535."
  fi
  if ss -tln | awk '{print $4}' | grep -qE "(:|\.)${MC_PORT}\$"; then
    fatal "$(cat <<EOF
Port $MC_PORT is already in use. Choose a different port using --port

To see what's using the port:
  sudo lsof -iTCP:$MC_PORT -sTCP:LISTEN
  sudo ss -tuln | grep $MC_PORT
EOF
)"
  fi

  local SRV_DIR="${MC_INSTANCES}/${MC_NAME}"
  local SRV_JAR="${SRV_DIR}/server.jar"
  local JVM_ARGS_FILE="${SRV_DIR}/jvm.args"
  local META_ENV_FILE="${SRV_DIR}/meta.env"

  ##############################################################################
  # players/GiB -> max-players
  local mem unit players
  if [[ "$MC_RAM" =~ ^([0-9]+)([GgMm])$ ]]; then
    mem="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]}"
    [[ "$unit" =~ [Mm] ]] && mem=$(( mem / 1024 ))
    (( mem < 1 )) && mem=1
    (( MC_RAM_RATIO < 1 )) && MC_RAM_RATIO=1
    players=$(( mem * MC_RAM_RATIO ))
    (( players > 100 )) && players=100
  else
    players=10
    warn "Could not parse --ram; defaulting max-players=${players}"
  fi

  ##############################################################################
  # Ensure user and directories exist
  if getent passwd "$MC_USER" >/dev/null 2>&1; then
    current_home="$(getent passwd "$MC_USER" | cut -d: -f6)"
    if [[ "$current_home" != "$MC_HOME" ]]; then
      fatal "$(cat <<EOF
User '$MC_USER' already exists with home '$current_home', expected: '$MC_HOME'

Fix it manually using one of the following:

  • Change home:
      sudo usermod -d $MC_HOME -m $MC_USER

  • Or delete and recreate:
      sudo /sbin/deluser --remove-home $MC_USER
      sudo /sbin/delgroup --only-if-empty $MC_USER

  • Then verify:
      getent passwd $MC_USER
      getent group  $MC_USER
EOF
)"
    fi
    info "Using existing user '$MC_USER' (home: $current_home)"
  else
    info "Creating system user '$MC_USER' with home '$MC_HOME'"
    sudo adduser --system --home "$MC_HOME" --shell /bin/bash --group "$MC_USER"
  fi
  for dir in "$MC_BIN" "$MC_BACKUPS" "$SRV_DIR"; do
    if [[ ! -d "$dir" ]]; then
      sudo mkdir -p "$dir"
      sudo chown -R "$MC_USER:$MC_USER" "$dir"
    fi
  done

  ##############################################################################
  # Setup Java if needed
  [[ -x "${TEMURIN_JAVA_BIN_PATH}/java" ]] \
    || fatal "Required Java ${REQUIRED_JAVA_VERSION} not found at ${TEMURIN_JAVA_BIN_PATH}"

  ##############################################################################
  # Ensure a server JAR exists
  get_latest_jar() { # $1=directory
    local dir="$1"
    find "$dir" -maxdepth 1 -name 'minecraft_server_*.jar' | sort -Vr | head -n1
  }

  local latest
  latest=$(get_latest_jar "$SRV_DIR")

  if [[ -z "$latest" ]]; then
    info "No server JAR found — downloading latest vanilla release …"
    download --type minecraft --dest "$SRV_DIR" --user "$MC_USER"

    # Recompute after download
    latest=$(get_latest_jar "$SRV_DIR")
    [[ -z "$latest" ]] && fatal "Download failed: no JAR present in $SRV_DIR"
  else
    info "Existing server JAR found: $(basename "$latest")"
  fi

  ##############################################################################
  # Setup Minecraft

  # Link server.jar to the newest JAR
  sudo -u "$MC_USER" ln -sf "$(basename "$latest")" "$SRV_JAR"

  # Accept EULA
  sudo -u "$MC_USER" bash -c "echo 'eula=true' > '${SRV_DIR}/eula.txt'"

  # Setup server.properties
  local wl_enabled=false
  [[ -n "${MC_WHITELIST:-}" ]] && wl_enabled=true
  sudo -u "$MC_USER" tee "${SRV_DIR}/server.properties" >/dev/null <<EOF
enforce-whitelist=${wl_enabled}
force-gamemode=true
gamemode=${MC_GAMEMODE}
max-players=${players}
online-mode=true
pvp=${MC_PVP}
server-port=${MC_PORT}
white-list=${wl_enabled}
motd=${MC_MOTD}
EOF

  # Setup JVM arguments file
  sudo -u "$MC_USER" tee "$JVM_ARGS_FILE" >/dev/null <<EOF
-Xms${MC_RAM}
-Xmx${MC_RAM}
-XX:+UseG1GC
-XX:+ParallelRefProcEnabled
-XX:MaxGCPauseMillis=200
-XX:+UnlockExperimentalVMOptions
-XX:+DisableExplicitGC
-XX:+AlwaysPreTouch
-XX:G1NewSizePercent=30
-XX:G1MaxNewSizePercent=40
-XX:G1HeapRegionSize=16M
-XX:G1ReservePercent=20
-XX:G1HeapWastePercent=5
-XX:G1MixedGCCountTarget=4
-XX:InitiatingHeapOccupancyPercent=15
-XX:SurvivorRatio=32
-XX:+PerfDisableSharedMem
-XX:MaxTenuringThreshold=1
-Dusing.aikars.flags=https://mcflags.emc.gs
-Daikars.new.flags=true
EOF

  # Setup metadata file
  cat <<EOF | sudo -u "$MC_USER" tee "$META_ENV_FILE" >/dev/null
NAME=$MC_NAME
PORT=$MC_PORT
MOTD="$MC_MOTD"
RAM=$MC_RAM
GAMEMODE=$MC_GAMEMODE
WHITELIST=$MC_WHITELIST
EOF

  info "Setup complete — instance files in ${SRV_DIR}"
  info "Start with: sudo -u ${MC_USER} ${TEMURIN_JAVA_BIN_PATH}/java \$(cat ${JVM_ARGS_FILE}) -jar ${SRV_JAR} nogui"
}
# End Setup function

################################################################################
run() {
  warn "Not yet implemented"
  exit 1
}
# End Run function

################################################################################
# CLI Parsing
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
  help,       Can show sub-help menus (e.g. setup -h)
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