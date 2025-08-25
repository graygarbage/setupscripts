#!/bin/bash
set -e

# 1. Install missing tools for Mason providers
echo "Installing Go, Rust, Ruby, PHP, Java, Julia..."
sudo apt-get update
sudo apt-get install -y golang rustc ruby php openjdk-11-jdk julia

# 2. Resolve Snacks image issues
echo "Installing tectonic, pdflatex, mmdc..."
sudo apt-get install -y tectonic latexmk
npm install -g mmdc

# 3. Fix Python provider issues
echo "Installing neovim npm package..."
npm install -g neovim

# 4. Install Perl module
echo "Installing Neovim::Ext Perl module..."
cpanm install App::cpanm
cpanm install Neovim::Ext

# 5. Install SQLite3 (optional)
echo "Installing SQLite3..."
sudo apt-get install -y sqlite3

# 6. Update PATH environment
echo "Updating PATH in ~/.zshrc..."
echo 'export PATH="/usr/local/go/bin:$PATH"' >>~/.zshrc
echo 'export PATH="/usr/bin/rustc:$PATH"' >>~/.zshrc
echo 'export PATH="/usr/bin/ruby:$PATH"' >>~/.zshrc
echo 'export PATH="/usr/bin/php:$PATH"' >>~/.zshrc
echo 'export PATH="/usr/bin/java:$PATH"' >>~/.zshrc
echo 'export PATH="/usr/bin/julia:$PATH"' >>~/.zshrc

# 7. Reconfigure terminal
echo "Configuring Neovim to use wezterm..."
echo 'let g:termui_handler = "wezterm"' >>~/.config/nvim/init.vim

# 8. Reinstall missing tools
echo "Reinstalling tectonic, pdflatex, mmdc..."
sudo apt-get install -y tectonic latexmk
npm install -g mmdc

echo "Script completed. Restart Neovim and run :LazyHealthCheck again."
