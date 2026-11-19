#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

SKIP_K8S=0
SKIP_DEVPOD=0
OPEN_NVIM=0
AGE_KEY_FILE_ARG=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Post-reboot setup: decrypts Age/SOPS secrets, installs Tree-sitter parsers,
configures Kubernetes (k3s), clones homelab, and initializes DevPod & Mise tools.

Options:
  --skip-k8s           Skip remote Kubernetes (k3s) SSH/SCP kubeconfig fetch
  --skip-devpod        Skip DevPod workspace creation
  --open-nvim          Launch interactive Neovim session at the end of the script
  --age-key-file PATH  Path to private Age key file for SOPS secret decryption
  --non-interactive    Run without interactive prompts
  -h, --help           Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-k8s)
      SKIP_K8S=1
      shift
      ;;
    --skip-devpod)
      SKIP_DEVPOD=1
      shift
      ;;
    --open-nvim)
      OPEN_NVIM=1
      shift
      ;;
    --age-key-file)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        err "--age-key-file requires a path argument"
        usage
        exit 1
      fi
      AGE_KEY_FILE_ARG="$2"
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

log "Starting post-reboot setup..."

detect_os
export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"

# 1. Ensure Age/SOPS tools and decrypt any SOPS-encrypted secrets (such as kubeconfig or env vars)
install_age_and_sops
ensure_age_key || true
decrypt_bootstrap_secrets

# 2. Install Tree-sitter parsers headlessly in Neovim (no Alacritty/GUI requirement)
if command -v nvim &>/dev/null; then
  log "Installing Tree-sitter parsers in headless Neovim..."
  nvim --headless -c "TSInstallSync css latex norg scss svelte typst vue" -c "qa" || \
    warn "Headless Tree-sitter installation returned non-zero; parsers will finish installing on next Neovim launch."
else
  warn "Neovim (nvim) is not installed; skipping Tree-sitter parser installation."
fi

# 3. Kubernetes (k3s) kubeconfig setup
mkdir -p "${HOME}/.kube"
chmod 700 "${HOME}/.kube"

if [[ "$SKIP_K8S" -eq 1 ]]; then
  log "Skipping Kubernetes setup (--skip-k8s specified)."
elif [[ -s "${HOME}/.kube/config" && "${FORCE_K8S_FETCH:-0}" != "1" ]]; then
  chmod 600 "${HOME}/.kube/config"
  log "Kubeconfig already exists at ${HOME}/.kube/config (via SOPS or previous run); skipping remote SCP fetch."
else
  log "Setting up Kubernetes kubeconfig..."
  KUBERNETES_IP="${KUBERNETES_IP:-192.168.1.31}"
  KUBERNETES_USER="${KUBERNETES_USER:-user}"
  KUBERNETES_REMOTE_PATH="${KUBERNETES_REMOTE_PATH:-/home/${KUBERNETES_USER}/k3s.yaml}"

  if is_interactive; then
    read -r -p "Enter the Kubernetes server IP [${KUBERNETES_IP}] (or type 'skip' to skip): " user_ip
    if [[ "${user_ip:-}" == "skip" ]]; then
      SKIP_K8S=1
    else
      KUBERNETES_IP="${user_ip:-$KUBERNETES_IP}"
    fi
  fi

  if [[ "$SKIP_K8S" -eq 0 ]]; then
    if is_interactive; then
      read -r -p "Enter the Kubernetes server username [${KUBERNETES_USER}]: " user_name
      KUBERNETES_USER="${user_name:-$KUBERNETES_USER}"
      KUBERNETES_REMOTE_PATH="${KUBERNETES_REMOTE_PATH:-/home/${KUBERNETES_USER}/k3s.yaml}"
    fi

    log "Adding SSH key to Kubernetes server ${KUBERNETES_USER}@${KUBERNETES_IP}..."
    if ssh-copy-id "${KUBERNETES_USER}@${KUBERNETES_IP}"; then
      mkdir -p "${HOME}/projects"
      tmp_k3s="$(mktemp)"
      log "Copying k3s.yaml from ${KUBERNETES_USER}@${KUBERNETES_IP}:${KUBERNETES_REMOTE_PATH}..."
      if scp "${KUBERNETES_USER}@${KUBERNETES_IP}:${KUBERNETES_REMOTE_PATH}" "$tmp_k3s"; then
        sed -i "s|server:.*|server: https://${KUBERNETES_IP}:6443|" "$tmp_k3s"
        install -m 0600 "$tmp_k3s" "${HOME}/.kube/config"
        log "Installed kubeconfig to ${HOME}/.kube/config (mode 0600)."
      else
        warn "Failed to copy k3s.yaml from ${KUBERNETES_IP}; continuing."
      fi
      rm -f "$tmp_k3s"
    else
      warn "Could not copy SSH ID to ${KUBERNETES_USER}@${KUBERNETES_IP}; skipping kubeconfig transfer."
    fi
  fi
fi

# 4. Clone and configure Homelab repository idempotently
mkdir -p "${HOME}/projects"
HOMELAB_REPO="${HOMELAB_REPO:-git@github.com:graygarbage/homelab.git}"
HOMELAB_DIR="${HOMELAB_DIR:-${HOME}/projects/homelab}"
DOTFILES_REPO="${DOTFILES_REPO:-git@github.com:graygarbage/dotfiles.git}"

if [[ "${SKIP_HOMELAB:-0}" != "1" && -n "$HOMELAB_REPO" ]]; then
  if clone_or_update_repo "$HOMELAB_REPO" "$HOMELAB_DIR"; then
    # Decrypt any SOPS-encrypted secrets inside the homelab repository if Age key is present
    if has_age_key && [[ -d "$HOMELAB_DIR" ]]; then
      while IFS= read -r -d '' enc_file; do
        dec_target="${enc_file/.enc/}"
        dec_target="${dec_target/.sops/}"
        if [[ "$dec_target" != "$enc_file" && ! -f "$dec_target" ]]; then
          sops_decrypt_file "$enc_file" "$dec_target" 0600 || warn "Could not decrypt $enc_file"
        fi
      done < <(find "$HOMELAB_DIR" -maxdepth 3 \( -name "*.enc.yaml" -o -name "*.enc.yml" -o -name "*.enc.json" -o -name "*.enc.env" -o -name "*.sops.yaml" \) -print0 2>/dev/null)
    fi

    if command -v mise &>/dev/null; then
      log "Trusting and installing mise tools in ${HOMELAB_DIR}..."
      (cd "$HOMELAB_DIR" && mise trust && mise install) || warn "mise install in homelab returned non-zero."
    fi

    # Configure .envrc idempotently
    append_line_if_missing 'export KUBECONFIG=/workspaces/homelab/kubeconfig' "${HOMELAB_DIR}/.envrc"

    # Copy kubeconfig into homelab workspace if available
    if [[ -f "${HOME}/.kube/config" ]]; then
      install -m 0600 "${HOME}/.kube/config" "${HOMELAB_DIR}/kubeconfig"
    fi

    # Setup DevPod with Docker provider idempotently
    if [[ "$SKIP_DEVPOD" -eq 0 ]] && command -v devpod &>/dev/null; then
      log "Ensuring DevPod docker provider is configured..."
      if ! devpod provider list 2>/dev/null | grep -qw docker; then
        devpod provider add docker || warn "DevPod docker provider could not be added."
      else
        log "DevPod docker provider is already registered."
      fi

      log "Starting DevPod workspace for homelab..."
      (
        cd "$HOMELAB_DIR"
        if [[ -n "$DOTFILES_REPO" ]]; then
          devpod up . --ide none --dotfiles "$DOTFILES_REPO" || warn "devpod up returned non-zero."
        else
          devpod up . --ide none || warn "devpod up returned non-zero."
        fi
      )
    fi
  else
    warn "Could not clone homelab repository '${HOMELAB_REPO}'. Set HOMELAB_REPO or SKIP_HOMELAB=1 to customize."
  fi
fi

# 5. Update chezmoi dotfiles if chezmoi is installed and initialized
if command -v chezmoi &>/dev/null; then
  if [[ -d "${HOME}/.local/share/chezmoi" ]] && [[ -n "$(ls -A "${HOME}/.local/share/chezmoi" 2>/dev/null)" ]]; then
    log "Updating chezmoi dotfiles..."
    chezmoi update || warn "chezmoi update returned non-zero."
  else
    log "chezmoi is installed but no source state found at ~/.local/share/chezmoi; skipping chezmoi update."
  fi
else
  log "chezmoi is not installed; skipping chezmoi update."
fi

# 6. Sync LazyVim plugins headlessly (and optionally open Neovim interactively if requested)
if command -v nvim &>/dev/null; then
  log "Syncing Neovim / LazyVim plugins headlessly..."
  nvim --headless "+Lazy! sync" +qa 2>/dev/null || true

  if [[ "$OPEN_NVIM" -eq 1 ]] && is_interactive; then
    log "Opening Neovim interactively..."
    nvim
  fi
fi

log "Post-setup completed successfully!"
