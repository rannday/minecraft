# shellcheck shell=bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source, do not run.">&2; return 1; }

export REQUIRED_JAVA_VERSION=21
export MC_VERSION_MANIFEST_URL="https://piston-meta.mojang.com/mc/game/version_manifest.json"

################################################################################
ensure_java() {
  info "Checking for 'java' in PATH …"
  if ! command -v java >/dev/null 2>&1; then
    warn "No 'java' found in PATH."
    return 1
  fi
  ACTIVE_JAVA_BIN="$(readlink -f "$(command -v java)")"
  return 0
}

#################################################################################
ensure_java_version() {
  echo "Checking Java version …"
  [[ -n "${ACTIVE_JAVA_BIN:-}" ]] || { warn "No active Java binary set."; return 1; }
  local ver_line ver_major
  ver_line="$("$ACTIVE_JAVA_BIN" -version 2>&1 | head -n1)"
  [[ -n "$ver_line" && "$ver_line" == *version* ]] || { warn "'$ACTIVE_JAVA_BIN' did not return a recognizable version string."; return 1; }
  if [[ $ver_line =~ \"([0-9]+)\.([0-9]+) ]]; then
    ver_major="${BASH_REMATCH[1]}"
    [[ $ver_major == 1 ]] && ver_major="${BASH_REMATCH[2]}"
  else
    ver_major="$(awk -F\" '{print $2}' <<<"$ver_line" | cut -d. -f1)"
  fi
  (( ver_major == REQUIRED_JAVA_VERSION )) || { warn "Java found at $ACTIVE_JAVA_BIN, but version is $ver_major — expected $REQUIRED_JAVA_VERSION."; return 1; }
  info "Java $ver_major found at $ACTIVE_JAVA_BIN (OK)"
  return 0
}

################################################################################
# Register and activate the provided Java bin path
register_java_alternatives() {
  local bin_dir="$1"
  local java_path="$bin_dir/java"
  local javac_path="$bin_dir/javac"

  [[ -x "$java_path" && -x "$javac_path" ]] || fatal "Expected binaries not found in $bin_dir"
  command -v update-alternatives >/dev/null || fatal "'update-alternatives' not found"

  if command -v java >/dev/null 2>&1; then
    local current_java
    current_java="$(readlink -f "$(command -v java)")"
    if [[ "$(readlink -f "$java_path")" == "$current_java" ]]; then
      info "Java already active at $current_java (no changes needed)"
      return 0
    fi
  fi

  if ! update-alternatives --query java 2>/dev/null | awk '/^Alternative: /{print $2}' | grep -Fxq "$java_path"; then
    info "Registering JDK in $bin_dir via update-alternatives …"
    sudo update-alternatives --install /usr/bin/java java "$java_path" 100 \
      --slave /usr/bin/javac javac "$javac_path"
  fi

  sudo update-alternatives --set java "$java_path"
  info "JDK in $bin_dir is now the active version."
}

################################################################################
ensure_temurin() {
  [[ -n "${ACTIVE_JAVA_BIN:-}" ]] || return 1
  local vendor
  vendor="$("$ACTIVE_JAVA_BIN" -XshowSettings:properties 2>&1 | awk -F'= ' '/^ {4}java.vendor =/{print $2}')"
  [[ "$vendor" == "Eclipse Adoptium" && "$ACTIVE_JAVA_BIN" == "/usr/lib/jvm/temurin-${REQUIRED_JAVA_VERSION}-jdk-${SYS_ARCH}/bin/java" ]]
}

################################################################################
install_temurin() {
  local repo_file="/etc/apt/sources.list.d/adoptium.list"
  local pkg="temurin-${REQUIRED_JAVA_VERSION}-jdk"
  local codename vendor

  info "Installing Temurin Java $REQUIRED_JAVA_VERSION …"

  if ensure_java && ensure_java_version && ensure_temurin; then
    info "Temurin Java ${REQUIRED_JAVA_VERSION} already active at ${ACTIVE_JAVA_BIN} (OK)"
    return 0
  fi

  require_packages_apt curl gnupg
  codename="$(. /etc/os-release; echo "$VERSION_CODENAME")"
  [[ -f /usr/share/keyrings/adoptium.gpg ]] || \
    curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | sudo tee /usr/share/keyrings/adoptium.gpg >/dev/null
  grep -q "packages.adoptium.net" "$repo_file" 2>/dev/null || \
    echo "deb [arch=${SYS_ARCH} signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $codename main" | sudo tee "$repo_file" >/dev/null

  dpkg -s "$pkg" >/dev/null 2>&1 || { sudo apt-get update -qq; sudo apt-get install -y "$pkg"; }

  [[ -x "/usr/lib/jvm/temurin-${REQUIRED_JAVA_VERSION}-jdk-${SYS_ARCH}/bin/java" ]] || fatal "Expected Java binary not found at /usr/lib/jvm/temurin-${REQUIRED_JAVA_VERSION}-jdk-${SYS_ARCH}/bin/java"

  register_java_alternatives "/usr/lib/jvm/temurin-${REQUIRED_JAVA_VERSION}-jdk-${SYS_ARCH}/bin"

  ensure_java || fatal "Java not found after activation"
  ensure_java_version || fatal "Java version mismatch after activation"
  vendor="$("$ACTIVE_JAVA_BIN" -XshowSettings:properties 2>&1 | awk -F'= ' '/^ {4}java.vendor =/{print $2}')"
  [[ "$vendor" == "Eclipse Adoptium" ]] || fatal "Activated Java vendor is '$vendor', expected 'Eclipse Adoptium'"

  info "Temurin Java ${REQUIRED_JAVA_VERSION} is now active."
}

install_oracle() {
  warn "Not implemented yet"
  return 1
}

install_openjdk() {
  warn "Not implemented yet"
  return 1
}