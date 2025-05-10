#!/bin/bash

set -euo pipefail

# Debugging function to print messages with timestamps
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log "Starting setup script..."

# Determine the OS type
OS_TYPE=""
if command -v apt &>/dev/null; then
  OS_TYPE="ubuntu"
elif command -v pacman &>/dev/null; then
  OS_TYPE="arch"
else
  log "Unsupported OS type. Exiting..."
  exit 1
fi

log "Detected OS type: $OS_TYPE"

# Function to wait for apt lock to be released
wait_for_apt_lock() {
  while fuser /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; do
    log "Waiting for APT lock to be released..."
    sleep 5
  done
}

# Prompt for Git email
read -p "Enter your email for Git configuration: " GIT_EMAIL

# Prompt for SSH key comment
read -p "Enter a comment for the SSH key: " SSH_COMMENT

# Update and Upgrade
log "Updating and upgrading system..."
wait_for_apt_lock
if [ "$OS_TYPE" == "ubuntu" ]; then
  sudo apt update && sudo apt upgrade -y
elif [ "$OS_TYPE" == "arch" ]; then
  sudo pacman -Syu --noconfirm
fi

# Install necessary packages
log "Installing necessary packages..."
wait_for_apt_lock
if [ "$OS_TYPE" == "ubuntu" ]; then
  sudo apt install -y alacritty nala zsh luarocks cargo imagemagick texlive-latex-base git wget vim
elif [ "$OS_TYPE" == "arch" ]; then
  sudo pacman -S --noconfirm alacritty zsh luarocks cargo imagemagick texlive-most git wget vim
fi

# Install GitHub CLI
log "Installing GitHub CLI..."
wait_for_apt_lock
type -p curl >/dev/null || sudo apt install curl -y
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg &&
  sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg &&
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null &&
  wait_for_apt_lock &&
  sudo apt update &&
  sudo apt install gh -y

# Check GitHub CLI authentication
log "Checking GitHub CLI authentication..."
if ! gh auth status &>/dev/null; then
  log "GitHub CLI is not authenticated. Opening a new terminal to authenticate..."
  if [ "$OS_TYPE" == "ubuntu" ]; then
    # Open a new terminal window and run gh auth login
    gnome-terminal -- bash -c "gh auth login; exec bash"
  elif [ "$OS_TYPE" == "arch" ]; then
    # Open a new terminal tab and run gh auth login
    alacritty --hold -e bash -c "gh auth login; exec bash"
  fi
  log "Please authenticate GitHub CLI in the new terminal window/tab."
  exit 1
fi

# Install tree-sitter
log "Installing tree-sitter..."
cargo install tree-sitter-cli

# Install mise
log "Installing mise..."
curl https://mise.run | sh

# Add mise to PATH and activate mise
log "Adding mise to PATH and activating mise..."
if [ "$OS_TYPE" == "ubuntu" ]; then
  echo "export PATH=\"$HOME/.local/bin:\$PATH\"" >>~/.bashrc
  echo "eval \"\$($(which mise) activate bash)\"" >>~/.bashrc
  echo "export PATH=\"$HOME/.local/bin:\$PATH\"" >>~/.zshrc
  echo "eval \"\$($(which mise) activate zsh)\"" >>~/.zshrc
elif [ "$OS_TYPE" == "arch" ]; then
  echo "export PATH=\"$HOME/.local/bin:\$PATH\"" >>~/.bashrc
  echo "eval \"\$($(which mise) activate bash)\"" >>~/.bashrc
  echo "export PATH=\"$HOME/.local/bin:\$PATH\"" >>~/.zshrc
  echo "eval \"\$($(which mise) activate zsh)\"" >>~/.zshrc
fi

# Source the shell configuration to activate mise immediately
source ~/.bashrc
source ~/.zshrc

# Create SSH key with a passphrase (optional)
read -s -p "Enter a passphrase for the SSH key (leave empty for no passphrase): " SSH_PASSPHRASE
echo
ssh-keygen -t rsa -b 4096 -C "$SSH_COMMENT" -N "$SSH_PASSPHRASE"

# Add SSH key to GitHub
log "Adding SSH key to GitHub..."
GH_SSH_KEY=$(cat ~/.ssh/id_rsa.pub)
gh ssh-key add --title "New Linux Machine" - <<<"${GH_SSH_KEY}"

# Setup Git
log "Setting up Git..."
git config --global user.email "$GIT_EMAIL"
git config --global user.name "graygarbage"

# Make a projects folder for GitHub repos
log "Making projects folder..."
mkdir -p ~/projects && cd ~/projects

# Clone the dotfiles git repo and make setup executable
log "Cloning dotfiles..."
git clone git@github.com:graygarbage/dotfiles.git && cd dotfiles && chmod +x setup && cd ..

# Run the setup script
log "Running dotfiles setup script..."
./dotfiles/setup

# Install Docker
log "Installing Docker..."
if [ "$OS_TYPE" == "ubuntu" ]; then
  wait_for_apt_lock
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  wait_for_apt_lock
  sudo apt update
  wait_for_apt_lock
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker ${USER}
elif [ "$OS_TYPE" == "arch" ]; then
  sudo pacman -S --noconfirm docker docker-compose
  sudo systemctl enable --now docker
  sudo usermod -aG docker ${USER}
fi

# Install devpod
log "Installing devpod..."
curl -L -o devpod "https://github.com/loft-sh/devpod/releases/latest/download/devpod-linux-amd64" && sudo install -c -m 0755 devpod /usr/local/bin && rm -f devpod

# Reboot to apply changes
log "Rebooting in 10 seconds. Press Ctrl+C to cancel..."
sleep 10
sudo reboot
