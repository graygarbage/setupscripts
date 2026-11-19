#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

SKIP_UPDATE=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install LazyVim / Mason language toolchains, Node.js & Perl providers,
Mermaid CLI, SQLite development headers, and terminal UI configuration.

Options:
  --skip-update        Skip initial system package repository upgrade
  --non-interactive    Run without interactive prompts
  -h, --help           Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-update)
      SKIP_UPDATE=1
      shift
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

log "Starting LazyVim health check and provider dependency setup..."

detect_os
if [[ "$SKIP_UPDATE" -eq 0 ]]; then
  update_system_packages
fi

# 1. Install language toolchains and prerequisites for Mason, NPM, CPAN, and SQLite across distros
log "Installing Mason toolchain prerequisites (Go, Rust, Ruby, PHP, Java, Node.js/NPM, Perl/cpanm, SQLite3)..."
case "$OS_FAMILY" in
  debian)
    install_packages golang rustc cargo ruby-full php-cli default-jdk nodejs npm perl cpanminus sqlite3 libsqlite3-dev latexmk
    install_optional_package julia
    install_optional_package tectonic
    ;;
  fedora)
    install_packages golang rust cargo ruby php-cli java-latest-openjdk-devel nodejs npm perl-App-cpanminus sqlite sqlite-devel latexmk
    install_optional_package julia
    install_optional_package tectonic
    ;;
  arch)
    install_packages go rust ruby php jdk-openjdk nodejs npm cpanminus sqlite texlive-binextra
    install_optional_package julia
    install_optional_package tectonic
    ;;
  suse)
    install_packages go rust cargo ruby php8 java-21-openjdk-devel nodejs npm perl-App-cpanminus sqlite3 sqlite3-devel
    ;;
  alpine)
    install_packages go rust cargo ruby php83 openjdk21 nodejs npm perl-app-cpanminus sqlite sqlite-dev
    ;;
esac

# 2. Configure user-local NPM prefix to avoid EACCES permission errors on global npm installs
NPM_GLOBAL_DIR="${HOME}/.local/share/npm-global"
mkdir -p "$NPM_GLOBAL_DIR"
if command -v npm &>/dev/null; then
  npm config set prefix "$NPM_GLOBAL_DIR"
  export PATH="${NPM_GLOBAL_DIR}/bin:${PATH}"

  log "Installing Mermaid CLI (@mermaid-js/mermaid-cli) and neovim NPM provider..."
  npm install -g @mermaid-js/mermaid-cli neovim || warn "npm global install of mermaid-cli/neovim failed; continuing."
else
  warn "npm is not available; skipping Mermaid CLI and Neovim Node.js provider installation."
fi

# 3. Install Perl Neovim::Ext module cleanly via cpanm (using correct syntax without 'install' subcommand)
if command -v cpanm &>/dev/null; then
  log "Installing Neovim::Ext Perl module via cpanm..."
  cpanm --local-lib="${HOME}/perl5" --notest Neovim::Ext || warn "cpanm Neovim::Ext installation returned non-zero; continuing."
else
  warn "cpanm is not available; skipping Perl Neovim::Ext provider installation."
fi

# 4. Update PATH in shell RC files idempotently using valid directory paths ONLY (never binary executable paths)
log "Updating directory entries in ~/.bashrc and ~/.zshrc..."
# shellcheck disable=SC2016
{
  if [[ -d "/usr/local/go/bin" ]]; then
    append_line_if_missing 'export PATH="/usr/local/go/bin:$PATH"' "${HOME}/.bashrc"
    append_line_if_missing 'export PATH="/usr/local/go/bin:$PATH"' "${HOME}/.zshrc"
  fi

  append_line_if_missing 'export PERL5LIB="$HOME/perl5/lib/perl5${PERL5LIB:+:$PERL5LIB}"' "${HOME}/.bashrc"
  append_line_if_missing 'export PERL5LIB="$HOME/perl5/lib/perl5${PERL5LIB:+:$PERL5LIB}"' "${HOME}/.zshrc"

  append_line_if_missing 'export PATH="$HOME/.local/share/npm-global/bin:$HOME/perl5/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' "${HOME}/.bashrc"
  append_line_if_missing 'export PATH="$HOME/.local/share/npm-global/bin:$HOME/perl5/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' "${HOME}/.zshrc"
}

# 5. Configure Neovim terminal handler safely in Lua without creating conflicting init.vim alongside init.lua
NVIM_CONFIG_DIR="${HOME}/.config/nvim"
if [[ -f "${NVIM_CONFIG_DIR}/init.lua" ]]; then
  mkdir -p "${NVIM_CONFIG_DIR}/lua/config"
  LUA_OPTIONS_FILE="${NVIM_CONFIG_DIR}/lua/config/options.lua"
  append_line_if_missing 'vim.g.termui_handler = "wezterm"' "$LUA_OPTIONS_FILE"
elif [[ -f "${NVIM_CONFIG_DIR}/init.vim" ]]; then
  append_line_if_missing 'let g:termui_handler = "wezterm"' "${NVIM_CONFIG_DIR}/init.vim"
else
  mkdir -p "${NVIM_CONFIG_DIR}/lua/config"
  append_line_if_missing 'vim.g.termui_handler = "wezterm"' "${NVIM_CONFIG_DIR}/lua/config/options.lua"
fi

log "LazyVim dependencies and providers configured. Restart Neovim and run :checkhealth."
