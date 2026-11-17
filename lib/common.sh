#!/usr/bin/env bash
# lib/common.sh - Shared multi-distro, idempotency, and Age/SOPS helpers for setupscripts

# Prevent multiple sourcing
if [[ -n "${_SETUPSCRIPTS_COMMON_LOADED:-}" ]]; then
  return 0
fi
_SETUPSCRIPTS_COMMON_LOADED=1

# Logging helpers
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] - $*"
}

warn() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] - $*" >&2
}

err() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] - $*" >&2
}

# Detect OS distribution and package manager family via /etc/os-release and fallbacks
OS_ID=""
OS_ID_LIKE=""
OS_FAMILY=""
OS_TYPE=""
PKG_MANAGER=""

detect_os() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_ID_LIKE="${ID_LIKE:-}"
  fi

  local combined="${OS_ID} ${OS_ID_LIKE}"
  case "$combined" in
    *ubuntu*)
      OS_FAMILY="debian"
      OS_TYPE="ubuntu"
      PKG_MANAGER="apt"
      ;;
    *debian*|*raspbian*|*pop*|*linuxmint*|*kali*)
      OS_FAMILY="debian"
      OS_TYPE="debian"
      PKG_MANAGER="apt"
      ;;
    *fedora*|*rhel*|*centos*|*rocky*|*almalinux*|*nobara*)
      OS_FAMILY="fedora"
      OS_TYPE="${OS_ID:-fedora}"
      PKG_MANAGER="dnf"
      ;;
    *arch*|*manjaro*|*endeavouros*|*cachyos*|*garuda*)
      OS_FAMILY="arch"
      OS_TYPE="arch"
      PKG_MANAGER="pacman"
      ;;
    *opensuse*|*suse*|*sles*)
      OS_FAMILY="suse"
      OS_TYPE="opensuse"
      PKG_MANAGER="zypper"
      ;;
    *alpine*)
      OS_FAMILY="alpine"
      OS_TYPE="alpine"
      PKG_MANAGER="apk"
      ;;
    *)
      if command -v apt-get &>/dev/null; then
        OS_FAMILY="debian"
        OS_TYPE="${OS_ID:-debian}"
        PKG_MANAGER="apt"
      elif command -v dnf &>/dev/null; then
        OS_FAMILY="fedora"
        OS_TYPE="${OS_ID:-fedora}"
        PKG_MANAGER="dnf"
      elif command -v pacman &>/dev/null; then
        OS_FAMILY="arch"
        OS_TYPE="arch"
        PKG_MANAGER="pacman"
      elif command -v zypper &>/dev/null; then
        OS_FAMILY="suse"
        OS_TYPE="opensuse"
        PKG_MANAGER="zypper"
      elif command -v apk &>/dev/null; then
        OS_FAMILY="alpine"
        OS_TYPE="alpine"
        PKG_MANAGER="apk"
      else
        err "Unsupported Linux distribution (${OS_ID:-unknown})."
        return 1
      fi
      ;;
  esac

  export OS_ID OS_ID_LIKE OS_FAMILY OS_TYPE PKG_MANAGER
  log "Detected OS: ID='${OS_ID:-unknown}', family='${OS_FAMILY}', pkg_manager='${PKG_MANAGER}'"
}

# Detect CPU architecture dynamically and normalize to amd64 / arm64
detect_arch() {
  local raw_arch
  raw_arch="$(uname -m)"
  case "$raw_arch" in
    x86_64|amd64)
      echo "amd64"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    armv7l|armv6l)
      echo "arm"
      ;;
    *)
      err "Unsupported CPU architecture: $raw_arch"
      return 1
      ;;
  esac
}

# Detect headless vs GUI session
is_headless() {
  if [[ "${HEADLESS:-0}" == "1" ]]; then
    return 0
  fi
  if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    return 0
  fi
  return 1
}

# Check if running in an interactive terminal
is_interactive() {
  if [[ "${NONINTERACTIVE:-0}" == "1" ]]; then
    return 1
  fi
  [[ -t 0 && -t 1 ]]
}

# Wait for APT/DPKG lock safely (handles missing fuser)
wait_for_apt_lock() {
  if [[ "${OS_FAMILY}" != "debian" ]]; then
    return 0
  fi
  if command -v fuser &>/dev/null; then
    while fuser /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; do
      log "Waiting for APT/DPKG lock to be released..."
      sleep 3
    done
  fi
}

# Unified system update & upgrade across distros
update_system_packages() {
  log "Updating system package repositories and upgrading installed packages..."
  case "$OS_FAMILY" in
    debian)
      wait_for_apt_lock
      sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
      wait_for_apt_lock
      sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
      ;;
    fedora)
      sudo dnf upgrade --refresh -y
      ;;
    arch)
      sudo pacman -Syu --noconfirm
      ;;
    suse)
      sudo zypper --non-interactive refresh
      sudo zypper --non-interactive update
      ;;
    alpine)
      sudo apk update && sudo apk upgrade
      ;;
    *)
      err "update_system_packages: unsupported OS_FAMILY '$OS_FAMILY'"
      return 1
      ;;
  esac
}

# Unified package installation across distros
install_packages() {
  if [[ $# -eq 0 ]]; then
    return 0
  fi
  log "Installing packages (${PKG_MANAGER}): $*"
  case "$OS_FAMILY" in
    debian)
      wait_for_apt_lock
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
      ;;
    fedora)
      sudo dnf install -y "$@"
      ;;
    arch)
      sudo pacman -S --needed --noconfirm "$@"
      ;;
    suse)
      sudo zypper --non-interactive install -y "$@"
      ;;
    alpine)
      sudo apk add "$@"
      ;;
    *)
      err "install_packages: unsupported OS_FAMILY '$OS_FAMILY'"
      return 1
      ;;
  esac
}

# Check if a package is available in the distro's repositories before installing
install_optional_package() {
  local pkg="$1"
  case "$OS_FAMILY" in
    debian)
      if apt-cache show "$pkg" &>/dev/null; then
        install_packages "$pkg"
      else
        warn "Package '$pkg' not found in APT repositories; skipping."
      fi
      ;;
    fedora)
      if dnf info "$pkg" &>/dev/null; then
        install_packages "$pkg"
      else
        warn "Package '$pkg' not found in DNF repositories; skipping."
      fi
      ;;
    arch)
      if pacman -Si "$pkg" &>/dev/null; then
        install_packages "$pkg"
      else
        warn "Package '$pkg' not found in Pacman repositories; skipping."
      fi
      ;;
    *)
      install_packages "$pkg" || warn "Could not install optional package '$pkg'; skipping."
      ;;
  esac
}

# Install GitHub CLI (gh) using the native package manager / official repo for each distro
install_github_cli() {
  if command -v gh &>/dev/null; then
    log "GitHub CLI (gh) is already installed."
    return 0
  fi

  log "Installing GitHub CLI (gh)..."
  case "$OS_FAMILY" in
    debian)
      install_packages curl gpg ca-certificates
      sudo install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
      sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
      local deb_arch
      deb_arch="$(dpkg --print-architecture)"
      echo "deb [arch=${deb_arch} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
      wait_for_apt_lock
      sudo apt-get update -y
      install_packages gh
      ;;
    fedora)
      install_packages gh
      ;;
    arch)
      install_packages github-cli
      ;;
    suse)
      install_packages gh
      ;;
    alpine)
      install_packages github-cli
      ;;
    *)
      err "Cannot install GitHub CLI on unsupported OS family: $OS_FAMILY"
      return 1
      ;;
  esac
}

# Install Age and SOPS across all supported distributions
install_age_and_sops() {
  # 1. Install age
  if ! command -v age &>/dev/null; then
    log "Installing age encryption tool..."
    case "$OS_FAMILY" in
      debian|fedora|arch|suse|alpine)
        install_packages age
        ;;
    esac
  else
    log "age is already installed."
  fi

  # 2. Install sops
  if command -v sops &>/dev/null; then
    log "sops is already installed."
    return 0
  fi

  log "Installing sops secret manager..."
  case "$OS_FAMILY" in
    arch|alpine)
      install_packages sops
      return 0
      ;;
    debian|fedora|suse)
      # Try native repo first if available
      if [[ "$OS_FAMILY" == "debian" ]] && apt-cache show sops &>/dev/null; then
        install_packages sops && return 0
      elif [[ "$OS_FAMILY" == "fedora" ]] && dnf info sops &>/dev/null; then
        install_packages sops && return 0
      elif [[ "$OS_FAMILY" == "suse" ]] && zypper info sops &>/dev/null; then
        install_packages sops && return 0
      fi
      ;;
  esac

  # Fallback: Download official SOPS release binary for current architecture
  local arch
  arch="$(detect_arch)"
  local sops_version="${SOPS_VERSION:-v3.9.4}"
  if command -v curl &>/dev/null; then
    local latest_tag
    latest_tag="$(curl -fsSL https://api.github.com/repos/getsops/sops/releases/latest 2>/dev/null | grep -m1 '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)"
    if [[ -n "$latest_tag" ]]; then
      sops_version="$latest_tag"
    fi
  fi

  local tmp_sops
  tmp_sops="$(mktemp)"
  log "Downloading SOPS ${sops_version} binary for linux/${arch}..."
  curl -fsSL -o "$tmp_sops" "https://github.com/getsops/sops/releases/download/${sops_version}/sops-${sops_version}.linux.${arch}"
  sudo install -m 0755 "$tmp_sops" /usr/local/bin/sops
  rm -f "$tmp_sops"
  log "Installed SOPS $(sops --version 2>/dev/null | head -n1 || echo "$sops_version") to /usr/local/bin/sops"
}

# Resolve and validate the user's private Age key for SOPS
# Supports SOPS_AGE_KEY, SOPS_AGE_KEY_FILE, or default ~/.config/sops/age/keys.txt
ensure_age_key() {
  local default_key_file="${HOME}/.config/sops/age/keys.txt"
  export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$default_key_file}"

  mkdir -p "$(dirname "$SOPS_AGE_KEY_FILE")"
  chmod 700 "$(dirname "$SOPS_AGE_KEY_FILE")"

  if [[ -n "${SOPS_AGE_KEY:-}" ]]; then
    log "Using private Age key provided via SOPS_AGE_KEY environment variable."
    return 0
  fi

  if [[ -s "$SOPS_AGE_KEY_FILE" ]]; then
    chmod 600 "$SOPS_AGE_KEY_FILE"
    log "Found private Age key at $SOPS_AGE_KEY_FILE"
    return 0
  fi

  # Check if user passed key path via AGE_KEY_SOURCE or placed age.agekey in repo root
  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
  if [[ -n "${AGE_KEY_SOURCE:-}" && -f "${AGE_KEY_SOURCE}" ]]; then
    install -m 0600 "$AGE_KEY_SOURCE" "$SOPS_AGE_KEY_FILE"
    log "Installed private Age key from $AGE_KEY_SOURCE to $SOPS_AGE_KEY_FILE"
    return 0
  elif [[ -f "${repo_root}/keys.txt" ]]; then
    install -m 0600 "${repo_root}/keys.txt" "$SOPS_AGE_KEY_FILE"
    log "Installed private Age key from ${repo_root}/keys.txt to $SOPS_AGE_KEY_FILE"
    return 0
  fi

  if is_interactive; then
    warn "No private Age key found at $SOPS_AGE_KEY_FILE (and SOPS_AGE_KEY is not set)."
    read -r -p "Enter path to your existing Age private key file (or press Enter to skip SOPS decryption): " user_key_path
    if [[ -n "$user_key_path" && -f "$user_key_path" ]]; then
      install -m 0600 "$user_key_path" "$SOPS_AGE_KEY_FILE"
      log "Copied Age private key to $SOPS_AGE_KEY_FILE (mode 0600)."
      return 0
    elif [[ -n "$user_key_path" ]]; then
      warn "File '$user_key_path' does not exist. Continuing without Age private key."
    else
      warn "Skipping Age key setup. Place your key at $SOPS_AGE_KEY_FILE to enable SOPS secret decryption."
    fi
  else
    warn "No Age key found at $SOPS_AGE_KEY_FILE. SOPS secret decryption will be skipped until key is provided."
  fi
  return 1
}

# Helper to check if an Age key is currently available for SOPS
has_age_key() {
  local key_file="${SOPS_AGE_KEY_FILE:-${HOME}/.config/sops/age/keys.txt}"
  [[ -n "${SOPS_AGE_KEY:-}" || -s "$key_file" ]]
}

# Decrypt a SOPS-encrypted file to stdout or to a target file with secure permissions
sops_decrypt_file() {
  local src_file="$1"
  local dst_file="${2:-}"
  local mode="${3:-0600}"

  if [[ ! -f "$src_file" ]]; then
    err "sops_decrypt_file: source file '$src_file' does not exist."
    return 1
  fi

  if ! command -v sops &>/dev/null; then
    err "sops_decrypt_file: 'sops' is not installed."
    return 1
  fi

  if ! has_age_key; then
    err "sops_decrypt_file: No Age private key configured (check ~/.config/sops/age/keys.txt or SOPS_AGE_KEY)."
    return 1
  fi

  if [[ -z "$dst_file" ]]; then
    sops --decrypt "$src_file"
  else
    mkdir -p "$(dirname "$dst_file")"
    local tmp_out
    tmp_out="$(mktemp)"
    if sops --decrypt "$src_file" >"$tmp_out"; then
      install -m "$mode" "$tmp_out" "$dst_file"
      rm -f "$tmp_out"
      log "Decrypted $src_file -> $dst_file (mode $mode)"
    else
      rm -f "$tmp_out"
      err "Failed to decrypt $src_file with SOPS."
      return 1
    fi
  fi
}

# Extract a specific key from a SOPS-encrypted YAML/JSON file (returns empty on failure/missing)
sops_extract_value() {
  local src_file="$1"
  local extract_path="$2"
  if [[ -f "$src_file" ]] && command -v sops &>/dev/null && has_age_key; then
    sops --decrypt --extract "$extract_path" "$src_file" 2>/dev/null || true
  fi
}

# Decrypt standard bootstrap secrets if encrypted files exist in the repository or secrets directory
decrypt_bootstrap_secrets() {
  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
  local secrets_dir="${SECRETS_DIR:-${repo_root}/secrets}"

  if [[ ! -d "$secrets_dir" ]]; then
    return 0
  fi

  if ! has_age_key; then
    warn "Secrets directory found at $secrets_dir, but no Age private key is available. Skipping secret decryption."
    return 0
  fi

  log "Checking for SOPS-encrypted bootstrap secrets in $secrets_dir..."

  # 1. Decrypt SSH private key if present (e.g. secrets/id_ed25519.enc)
  if [[ -f "${secrets_dir}/id_ed25519.enc" && ! -f "${HOME}/.ssh/id_ed25519" ]]; then
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    sops_decrypt_file "${secrets_dir}/id_ed25519.enc" "${HOME}/.ssh/id_ed25519" 0600
    ssh-keygen -y -f "${HOME}/.ssh/id_ed25519" >"${HOME}/.ssh/id_ed25519.pub"
    chmod 644 "${HOME}/.ssh/id_ed25519.pub"
    log "Restored SSH keypair from SOPS secret ${secrets_dir}/id_ed25519.enc"
  fi

  # 2. Decrypt kubeconfig if present (e.g. secrets/kubeconfig.enc.yaml or secrets/k3s.enc.yaml)
  for kube_secret in "${secrets_dir}/kubeconfig.enc.yaml" "${secrets_dir}/k3s.enc.yaml"; do
    if [[ -f "$kube_secret" ]]; then
      mkdir -p "${HOME}/.kube"
      chmod 700 "${HOME}/.kube"
      sops_decrypt_file "$kube_secret" "${HOME}/.kube/config" 0600
      break
    fi
  done

  # 3. Load bootstrap environment variables from secrets/bootstrap.enc.env if present
  if [[ -f "${secrets_dir}/bootstrap.enc.env" ]]; then
    log "Loading bootstrap configuration from ${secrets_dir}/bootstrap.enc.env..."
    local decrypted_env
    if decrypted_env="$(sops --decrypt "${secrets_dir}/bootstrap.enc.env" 2>/dev/null)"; then
      while IFS='=' read -r k v; do
        [[ -z "$k" || "$k" =~ ^[[:space:]]*# ]] && continue
        k="${k#export }"
        k="${k#"${k%%[![:space:]]*}"}"
        k="${k%"${k##*[![:space:]]}"}"
        v="${v%$'\r'}"
        if [[ "$v" =~ ^\"(.*)\"$ ]]; then
          v="${BASH_REMATCH[1]}"
        elif [[ "$v" =~ ^\'(.*)\'$ ]]; then
          v="${BASH_REMATCH[1]}"
        fi
        export "$k=$v"
      done <<<"$decrypted_env"
    else
      warn "Failed to decrypt ${secrets_dir}/bootstrap.enc.env; skipping bootstrap env load."
    fi
  fi
}

# Idempotently append a line to a file if not already present
append_line_if_missing() {
  local line="$1"
  local file="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if ! grep -qxF "$line" "$file" 2>/dev/null; then
    echo "$line" >>"$file"
    log "Added configuration line to $file"
  fi
}

# Idempotently clone or update a git repository
clone_or_update_repo() {
  local repo_url="$1"
  local target_dir="$2"

  if [[ -z "$repo_url" ]]; then
    warn "clone_or_update_repo: empty repository URL; skipping."
    return 0
  fi

  if [[ -d "${target_dir}/.git" ]]; then
    log "Repository already exists at ${target_dir}; pulling latest changes..."
    git -C "$target_dir" pull --ff-only || warn "Could not fast-forward ${target_dir}; continuing with existing checkout."
  elif [[ -d "$target_dir" && -n "$(ls -A "$target_dir" 2>/dev/null)" ]]; then
    warn "Directory ${target_dir} already exists and is not a git repository; skipping clone."
  else
    mkdir -p "$(dirname "$target_dir")"
    log "Cloning ${repo_url} into ${target_dir}..."
    git clone "$repo_url" "$target_dir"
  fi
}
