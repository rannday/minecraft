#!/usr/bin/env bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source, do not run.">&2; return 1; }

export REQUIRED_JAVA_VERSION=21
export MC_VERSION_MANIFEST_URL="https://piston-meta.mojang.com/mc/game/version_manifest.json"

################################################################################
require_packages_apt() {
  local missing=()

  # Collect missing packages
  for pkg in "$@"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
      missing+=("$pkg")
    fi
  done

  # All present → nothing to do
  [[ ${#missing[@]} -eq 0 ]] && return 0

  info "Installing required packages..."
  sudo apt-get update -qq
  sudo apt-get install -y "${missing[@]}"
}

################################################################################
# Ensure the correct version of Java is installed and active
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

  if (( ver_major != REQUIRED_JAVA_VERSION )); then
    warn "Java found at $java_bin, but version is $ver_major — expected $REQUIRED_JAVA_VERSION."
    return 1
  fi

  info "Java $ver_major found at $java_bin (OK)"
  return 0
}

################################################################################
# Register and activate the provided Java bin path
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
    sudo update-alternatives --install /usr/bin/java java "$java_path" 100 \
      --slave /usr/bin/javac javac "$javac_path"
  fi

  # Set as default
  sudo update-alternatives --set java  "$java_path"

  info "JDK in $bin_dir is now the active version."
}


