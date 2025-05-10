#!/bin/bash

set -euo pipefail

# Debugging function to print messages with timestamps
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log "Starting post-reboot setup..."

# Open Alacritty and run Neovim
log "Opening Alacritty and running Neovim..."
alacritty -e nvim -c ":TSInstall css latex norg scss svelte typst vue" -c ":q!"

# Kubernetes setup
log "Setting up Kubernetes..."

# Prompt for Kubernetes server IP
KUBERNETES_IP="${KUBERNETES_IP:-192.168.1.31}"
read -p "Enter the Kubernetes server IP [${KUBERNETES_IP}]: " USER_IP
KUBERNETES_IP=${USER_IP:-$KUBERNETES_IP}

# Prompt for Kubernetes server username
KUBERNETES_USER="${KUBERNETES_USER:-user}"
read -p "Enter the Kubernetes server username [${KUBERNETES_USER}]: " USER_NAME
KUBERNETES_USER=${USER_NAME:-$KUBERNETES_USER}

# Add your new SSH key to the Kubernetes server
log "Adding SSH key to Kubernetes server..."
ssh-copy-id "${KUBERNETES_USER}@${KUBERNETES_IP}"

# Copy the k3s.yaml file to the new Linux machine
log "Copying k3s.yaml file..."
scp "${KUBERNETES_USER}@${KUBERNETES_IP}:/home/${KUBERNETES_USER}/k3s.yaml" ~/projects/

# Edit the k3s.yaml file to point to the Kubernetes IP
log "Editing k3s.yaml file..."
sed -i "s/server:.*/server: https:\/\/${KUBERNETES_IP}:6443/" ~/projects/k3s.yaml

# Setup kubectl
log "Setting up kubectl..."
mkdir -p ~/.kube
mv ~/projects/k3s.yaml ~/.kube/config

# Configure devpods with Docker and Homelab
log "Configuring devpods with Docker and Homelab..."
cd ~/projects
git clone git@github.com:graygarbage/homelab.git && cd homelab && mise trust

# Setup devpod with Docker provider
log "Setting up devpod with Docker provider..."
devpod provider add docker

# Setup .envrc file
log "Setting up .envrc file..."
echo 'export KUBECONFIG=/workspaces/homelab/kubeconfig' >.envrc

# Copy kubeconfig file
log "Copying kubeconfig file..."
cp ~/.kube/config ~/projects/homelab/kubeconfig

# Build the devpod with dotfiles
log "Building devpod with dotfiles..."
devpod up . --ide none --dotfiles git@github.com:graygarbage/dotfiles.git

# Confirm dotfiles are correct
log "Confirming dotfiles are correct..."
chezmoi update

# Install project specific tools with mise
log "Installing project specific tools with mise..."
mise install

# Open Neovim again to allow LazyVIM to install tools
log "Opening Neovim to allow LazyVIM to install tools..."
nvim
