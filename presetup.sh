#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

NO_REBOOT=0
AUTO_REBOOT=0
AGE_KEY_FILE_ARG=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Bootstrap a Linux machine across Fedora, Ubuntu, Debian, Arch, openSUSE, or Alpine.

Options:
  --no-reboot          Do not reboot or prompt to reboot at the end of setup
  --reboot             Reboot automatically at the end of setup
  --age-key-file PATH  Path to private Age key file to install to ~/.config/sops/age/keys.txt
  --non-interactive    Run without interactive prompts (uses environment variables/defaults)
  -h, --help           Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-reboot)
      NO_REBOOT=1
      shift
      ;;
    --reboot)
      AUTO_REBOOT=1
      shift
      ;;
    --age-key-file)
      AGE_KEY_FILE_ARG="${2:-}"
      shift 2
      ;;
    --non-interactive)
      export NONINTERACTIVE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -n "$AGE_KEY_FILE_ARG" ]]; then
  export AGE_KEY_SOURCE="$AGE_KEY_FILE_ARG"
fi

log "Starting presetup script..."

# 1. Detect OS and architecture
detect_os
ARCH="$(detect_arch)"
log "Detected CPU architecture: $ARCH"

# 2. Update and upgrade system packages
update_system_packages

# 3. Install core packages across distros (including neovim, curl, git, zsh, etc.)
log "Installing core packages..."
COMMON_PACKAGES=(git curl wget zsh neovim vim luarocks cargo imagemagick)

case "$OS_FAMILY" in
  debian)
    install_packages "${COMMON_PACKAGES[@]}" ca-certificates gnupg lsb-release texlive-latex-base
    ;;
  fedora)
    install_packages "${COMMON_PACKAGES[@]}" ca-certificates gnupg2 texlive-scheme-basic
    ;;
  arch)
    install_packages "${COMMON_PACKAGES[@]}" ca-certificates gnupg texlive-basic
    ;;
  suse)
    install_packages "${COMMON_PACKAGES[@]}" ca-certificates gpg2 texlive-scheme-basic
    ;;
  alpine)
    install_packages "${COMMON_PACKAGES[@]}" ca-certificates gnupg
    ;;
esac

# Install Alacritty only when running on a desktop/GUI environment (or if available and not headless)
if ! is_headless; then
  install_optional_package alacritty
else
  log "Headless session detected; skipping GUI terminal emulator (alacritty)."
fi

# 4. Install Age and SOPS and configure Age key / decrypt bootstrap secrets
install_age_and_sops
ensure_age_key || true
decrypt_bootstrap_secrets

# 5. Gather Git and SSH configuration (from decrypted secrets, env vars, or interactive prompt)
GIT_NAME="${GIT_NAME:-$(git config --global user.name 2>/dev/null || true)}"
if [[ -z "$GIT_NAME" ]] && is_interactive; then
  read -r -p "Enter your name for Git configuration [graygarbage]: " input_name
  GIT_NAME="${input_name:-graygarbage}"
fi
GIT_NAME="${GIT_NAME:-graygarbage}"

GIT_EMAIL="${GIT_EMAIL:-$(git config --global user.email 2>/dev/null || true)}"
if [[ -z "$GIT_EMAIL" ]] && is_interactive; then
  read -r -p "Enter your email for Git configuration: " GIT_EMAIL
fi

SSH_COMMENT="${SSH_COMMENT:-${GIT_EMAIL:-${USER}@$(hostname -s 2>/dev/null || echo linux)}}"
if is_interactive && [[ -z "${SSH_COMMENT_SET:-}" ]]; then
  read -r -p "Enter a comment for the SSH key [${SSH_COMMENT}]: " input_comment
  SSH_COMMENT="${input_comment:-$SSH_COMMENT}"
fi

# 6. Install and authenticate GitHub CLI
install_github_cli

log "Checking GitHub CLI authentication..."
if ! gh auth status &>/dev/null; then
  if [[ -n "${GH_TOKEN:-}" || -n "${GITHUB_TOKEN:-}" ]]; then
    log "GitHub token detected in environment; skipping interactive gh auth login."
  elif is_interactive; then
    log "GitHub CLI is not authenticated. Starting inline authentication..."
    gh auth login || warn "GitHub CLI authentication was not completed; continuing."
  else
    warn "GitHub CLI is not authenticated and session is non-interactive. Set GH_TOKEN or run 'gh auth login' later."
  fi
else
  log "GitHub CLI is already authenticated."
fi

# 7. Install tree-sitter-cli
export PATH="${HOME}/.cargo/bin:${HOME}/.local/bin:${PATH}"
if ! command -v tree-sitter &>/dev/null; then
  log "Installing tree-sitter-cli..."
  case "$OS_FAMILY" in
    arch)
      install_packages tree-sitter-cli
      ;;
    *)
      if ! install_optional_package tree-sitter-cli || ! command -v tree-sitter &>/dev/null; then
        cargo install tree-sitter-cli
      fi
      ;;
  esac
else
  log "tree-sitter-cli is already installed."
fi

# 8. Install mise idempotently
MISE_BIN="${HOME}/.local/bin/mise"
if ! command -v mise &>/dev/null && [[ ! -x "$MISE_BIN" ]]; then
  log "Installing mise..."
  curl -fsSL https://mise.run | sh
else
  log "mise is already installed."
fi

# 9. Configure shell RC files idempotently without evaluating $(which mise) prematurely or sourcing .zshrc in bash
log "Configuring PATH and mise activation in ~/.bashrc and ~/.zshrc..."
# shellcheck disable=SC2016
{
  append_line_if_missing 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' "${HOME}/.bashrc"
  append_line_if_missing 'eval "$("$HOME/.local/bin/mise" activate bash)"' "${HOME}/.bashrc"

  append_line_if_missing 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' "${HOME}/.zshrc"
  append_line_if_missing 'eval "$("$HOME/.local/bin/mise" activate zsh)"' "${HOME}/.zshrc"
}

# Activate mise in current bash execution environment safely
if [[ -x "$MISE_BIN" ]]; then
  eval "$("$MISE_BIN" activate bash)"
elif command -v mise &>/dev/null; then
  eval "$(mise activate bash)"
fi

# 10. Generate SSH key idempotently (prefer Ed25519, respect existing keys)
mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"

SSH_KEY_PATH="${SSH_KEY_PATH:-${HOME}/.ssh/id_ed25519}"
if [[ ! -f "$SSH_KEY_PATH" && -f "${HOME}/.ssh/id_rsa" ]]; then
  SSH_KEY_PATH="${HOME}/.ssh/id_rsa"
  log "Existing RSA SSH key found at ${SSH_KEY_PATH}; reusing it."
elif [[ -f "$SSH_KEY_PATH" ]]; then
  log "SSH key already exists at ${SSH_KEY_PATH}; skipping generation."
else
  SSH_PASSPHRASE="${SSH_PASSPHRASE:-}"
  if is_interactive; then
    read -r -s -p "Enter a passphrase for the new SSH key (leave empty for no passphrase): " SSH_PASSPHRASE
    echo
  fi
  log "Generating Ed25519 SSH key at ${SSH_KEY_PATH}..."
  ssh-keygen -t ed25519 -C "$SSH_COMMENT" -f "$SSH_KEY_PATH" -N "$SSH_PASSPHRASE"
fi

# 11. Upload SSH public key to GitHub idempotently if gh is authenticated
SSH_PUB_PATH="${SSH_KEY_PATH}.pub"
if [[ -f "$SSH_PUB_PATH" ]] && gh auth status &>/dev/null; then
  PUB_KEY_CONTENT="$(awk '{print $1" "$2}' "$SSH_PUB_PATH")"
  EXISTING_KEYS="$(gh ssh-key list 2>/dev/null || true)"
  if [[ -n "$PUB_KEY_CONTENT" ]] && grep -qF "$(awk '{print $2}' "$SSH_PUB_PATH")" <<<"$EXISTING_KEYS"; then
    log "SSH public key is already registered on GitHub; skipping upload."
  else
    KEY_TITLE="${SSH_KEY_TITLE:-Linux-$(hostname -s 2>/dev/null || echo workstation)-$(date '+%Y%m%d')}"
    log "Adding SSH public key to GitHub with title '${KEY_TITLE}'..."
    gh ssh-key add "$SSH_PUB_PATH" --title "$KEY_TITLE" || warn "Failed to add SSH key to GitHub (it may already exist)."
  fi
else
  warn "Skipping GitHub SSH key upload (either public key missing or gh CLI not authenticated)."
fi

# 12. Configure Git global identity
log "Configuring global Git settings..."
if [[ -n "$GIT_EMAIL" ]]; then
  git config --global user.email "$GIT_EMAIL"
fi
if [[ -n "$GIT_NAME" ]]; then
  git config --global user.name "$GIT_NAME"
fi

# 13. Clone dotfiles repository idempotently
mkdir -p "${HOME}/projects"
DOTFILES_REPO="${DOTFILES_REPO:-git@github.com:graygarbage/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-${HOME}/projects/dotfiles}"

if [[ "${SKIP_DOTFILES:-0}" != "1" && -n "$DOTFILES_REPO" ]]; then
  if clone_or_update_repo "$DOTFILES_REPO" "$DOTFILES_DIR"; then
    if [[ -f "${DOTFILES_DIR}/setup" ]]; then
      chmod +x "${DOTFILES_DIR}/setup"
      log "Running dotfiles setup script..."
      (cd "$DOTFILES_DIR" && ./setup)
    fi
  else
    warn "Could not clone dotfiles repository '${DOTFILES_REPO}'. Set DOTFILES_REPO or SKIP_DOTFILES=1 to customize."
  fi
fi

# 14. Install Docker across distros
install_docker() {
  if command -v docker &>/dev/null; then
    log "Docker is already installed."
  else
    log "Installing Docker for ${OS_FAMILY} (${OS_TYPE})..."
    case "$OS_FAMILY" in
      debian)
        install_packages ca-certificates curl
        sudo install -m 0755 -d /etc/apt/keyrings
        local docker_distro="ubuntu"
        if [[ "$OS_ID" == "debian" || "$OS_TYPE" == "debian" ]]; then
          docker_distro="debian"
        fi
        sudo curl -fsSL "https://download.docker.com/linux/${docker_distro}/gpg" -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc
        local codename=""
        if [[ -f /etc/os-release ]]; then
          # shellcheck disable=SC1091
          codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
        fi
        if [[ -z "$codename" ]] && command -v lsb_release &>/dev/null; then
          codename="$(lsb_release -cs)"
        fi
        local deb_arch
        deb_arch="$(dpkg --print-architecture)"
        echo "deb [arch=${deb_arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${docker_distro} ${codename} stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
        wait_for_apt_lock
        sudo apt-get update -y
        install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        ;;
      fedora)
        sudo dnf -y install dnf-plugins-core
        if dnf config-manager --help 2>&1 | grep -q -- '--add-repo'; then
          sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo || true
        else
          sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo || true
        fi
        if dnf info docker-ce &>/dev/null; then
          install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        else
          install_packages moby-engine docker-compose
        fi
        ;;
      arch)
        install_packages docker docker-compose docker-buildx
        ;;
      suse)
        install_packages docker docker-compose
        ;;
      alpine)
        install_packages docker docker-cli-compose
        ;;
    esac
  fi

  if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
    sudo systemctl enable --now docker || warn "Could not enable/start docker service via systemctl."
  fi

  if getent group docker &>/dev/null && [[ -n "${USER:-}" ]]; then
    sudo usermod -aG docker "${USER}" || warn "Could not add ${USER} to docker group."
  fi
}

install_docker

# 15. Install DevPod dynamically for the detected CPU architecture
if ! command -v devpod &>/dev/null; then
  log "Installing DevPod for linux-${ARCH}..."
  tmp_devpod="$(mktemp)"
  curl -fsSL -o "$tmp_devpod" "https://github.com/loft-sh/devpod/releases/latest/download/devpod-linux-${ARCH}"
  sudo install -c -m 0755 "$tmp_devpod" /usr/local/bin/devpod
  rm -f "$tmp_devpod"
else
  log "DevPod is already installed."
fi

# 16. Handle reboot gracefully
log "Presetup complete!"
if [[ "$NO_REBOOT" -eq 1 ]]; then
  log "Skipping reboot (--no-reboot specified)."
elif [[ "$AUTO_REBOOT" -eq 1 ]]; then
  log "Rebooting in 10 seconds (--reboot specified). Press Ctrl+C to cancel..."
  sleep 10
  sudo reboot
elif is_interactive; then
  read -r -p "Would you like to reboot now to apply group and kernel changes? [y/N]: " reboot_choice
  if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
    log "Rebooting..."
    sudo reboot
  else
    log "Reboot skipped. Log out and back in (or reboot later) before running ./postsetup.sh."
  fi
else
  log "Non-interactive session: skipping automatic reboot. Pass --reboot to force reboot."
fi
