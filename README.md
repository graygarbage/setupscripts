# Setup Scripts

Resilient, idempotent bootstrapping scripts to take a fresh Linux installation from a bare OS to a fully configured developer workstation or headless server.

Supports native **Age + SOPS** secret management, automatic OS/architecture detection, **GitHub CLI** & **SSH** provisioning, **Dotfiles** & **Chezmoi** synchronization, **Docker** + **DevPod** workspace initialization, **Kubernetes (`k3s`)** kubeconfig import, **Mise** runtime management, and **Neovim / LazyVim** language toolchains.

---

## Table of Contents

1. [Lifecycle Overview](#lifecycle-overview)
2. [Repository Structure](#repository-structure)
3. [Supported Linux Distributions & Architectures](#supported-linux-distributions--architectures)
4. [SOPS & Age Secret Management Flow](#sops--age-secret-management-flow)
5. [Quick Start](#quick-start)
6. [Detailed Execution Flow](#detailed-execution-flow)
   - [Shared Library (`lib/common.sh`)](#shared-library-libcommonsh)
   - [Stage 1: Pre-Setup (`presetup.sh`)](#stage-1-pre-setup-presetupsh)
   - [Stage 2: Post-Setup (`postsetup.sh`)](#stage-2-post-setup-postsetupsh)
   - [Stage 3: LazyVim & Mason Toolchains (`fix_lazyvim.sh`)](#stage-3-lazyvim--mason-toolchains-fix_lazyvimsh)
7. [CLI Flags & Environment Variables](#cli-flags--environment-variables)
8. [Usage Recipes (Desktop, Headless, Unattended)](#usage-recipes-desktop-headless-unattended)
9. [Troubleshooting Guide](#troubleshooting-guide)
10. [License](#license)

---

## Lifecycle Overview

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ Stage 0: Initial Clone & Age Key Placement                                  │
│   git clone https://github.com/graygarbage/setupscripts.git                 │
│   Place private Age key at ~/.config/sops/age/keys.txt (or SOPS_AGE_KEY)    │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ Stage 1: ./presetup.sh                                                      │
│   • Detect OS family (dnf / apt / pacman / zypper / apk) & CPU arch         │
│   • Upgrade packages & install core CLI tools (git, zsh, nvim, cargo, etc.) │
│   • Install Alacritty (GUI sessions only; automatically skipped headless)   │
│   • Install Age & SOPS; decrypt secrets/ (SSH key, kubeconfig, env vars)    │
│   • Authenticate GitHub CLI (gh), generate/reuse Ed25519 SSH key & upload   │
│   • Install tree-sitter-cli & mise; configure ~/.bashrc and ~/.zshrc        │
│   • Clone dotfiles repo (~/projects/dotfiles) & run ./setup                 │
│   • Install Docker Engine + Compose, enable service, add $USER to docker    │
│   • Install DevPod CLI binary for detected architecture                     │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                         (Reboot or re-login to apply
                          docker group & shell changes)
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ Stage 2: ./postsetup.sh                                                     │
│   • Verify Age/SOPS & decrypt any pending bootstrap secrets                 │
│   • Compile Neovim Tree-sitter parsers headlessly (TSInstallSync)           │
│   • Configure ~/.kube/config (from SOPS secret or remote k3s via SSH/SCP)   │
│   • Clone homelab repo (~/projects/homelab), decrypt *.enc.* secrets        │
│   • Run mise trust & mise install; configure .envrc & workspace kubeconfig  │
│   • Register DevPod Docker provider & launch homelab DevPod workspace       │
│   • Update Chezmoi dotfiles (if initialized) & sync LazyVim plugins         │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ Stage 3: ./fix_lazyvim.sh (Optional)                                        │
│   • Install Mason language compilers & runtimes (Go, Rust, Ruby, PHP, JDK,  │
│     Node/NPM, Perl/cpanm, SQLite3 + headers, LaTeX/latexmk, Julia/Tectonic) │
│   • Configure user-local NPM prefix (~/.local/share/npm-global)             │
│   • Install @mermaid-js/mermaid-cli & Neovim Node.js / Perl providers       │
│   • Configure PATH, PERL5LIB, and Lua vim.g.termui_handler = "wezterm"      │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Repository Structure

| Path | Purpose |
| :--- | :--- |
| [`presetup.sh`](presetup.sh) | Stage 1 bootstrap script: packages, Age/SOPS, Git/GitHub/SSH, `tree-sitter-cli`, `mise`, dotfiles, Docker, DevPod. |
| [`postsetup.sh`](postsetup.sh) | Stage 2 post-login/reboot script: headless Tree-sitter parsers, `k3s` kubeconfig, `homelab` repo, DevPod workspace, Chezmoi, LazyVim sync. |
| [`fix_lazyvim.sh`](fix_lazyvim.sh) | Stage 3 toolchain script: language compilers/runtimes for Mason, rootless NPM global prefix, Perl `Neovim::Ext`, Mermaid CLI, Neovim health fixes. |
| [`lib/common.sh`](lib/common.sh) | Shared library providing OS/arch detection, package manager wrappers, APT lock handling, Age/SOPS encryption helpers, and idempotent file/git utilities. |
| [`.sops.yaml`](.sops.yaml) | SOPS creation rules mapping `secrets/*` and `*.enc.*` / `*.sops.*` files to public Age recipient key(s). |
| `secrets/` *(optional)* | Directory for SOPS-encrypted bootstrap artifacts (`id_ed25519.enc`, `kubeconfig.enc.yaml`, `k3s.enc.yaml`, `bootstrap.enc.env`). |

---

## Supported Linux Distributions & Architectures

`lib/common.sh` inspects `/etc/os-release` (`ID` and `ID_LIKE`) with automatic binary fallback to detect the distribution family and native package manager:

| Distribution Family | Package Manager | Supported Distributions | Core & Toolchain Specifics |
| :--- | :--- | :--- | :--- |
| **Fedora / RHEL** | `dnf` | Fedora, RHEL, CentOS Stream, Rocky Linux, AlmaLinux, Nobara | Uses `dnf upgrade --refresh`, official `docker-ce` repo (fallback to `moby-engine`), `texlive-scheme-basic`, `java-latest-openjdk-devel`, `perl-App-cpanminus`, `sqlite-devel`. |
| **Ubuntu / Debian** | `apt` | Ubuntu, Debian, Pop!\_OS, Linux Mint, Raspberry Pi OS (`raspbian`), Kali | Waits for APT/DPKG locks (`wait_for_apt_lock`), configures official GitHub CLI & Docker APT keyrings (`/etc/apt/keyrings`), `texlive-latex-base`, `default-jdk`, `cpanminus`, `libsqlite3-dev`. |
| **Arch Linux** | `pacman` | Arch Linux, Manjaro, EndeavourOS, CachyOS, Garuda | Non-interactive `pacman -S --needed --noconfirm`, native `github-cli`, `age`, `sops`, `tree-sitter-cli`, `texlive-basic`, `texlive-binextra`, `jdk-openjdk`. |
| **openSUSE / SUSE** | `zypper` | openSUSE Tumbleweed, openSUSE Leap, SLES | Non-interactive `zypper --non-interactive`, `gpg2`, `texlive-scheme-basic`, `java-21-openjdk-devel`, `sqlite3-devel`. |
| **Alpine Linux** | `apk` | Alpine Linux | Lightweight container/server support via `apk update && apk upgrade` and `apk add`. |

### CPU Architectures

`detect_arch` dynamically normalizes `uname -m` across all binary downloads (SOPS fallback, DevPod, Docker APT repos):
- `x86_64` / `amd64` → `amd64`
- `aarch64` / `arm64` → `arm64`
- `armv7l` / `armv6l` → `arm`

---

## SOPS & Age Secret Management Flow

All sensitive bootstrap artifacts (SSH private keys, Kubernetes configs, environment variables, and homelab secrets) are encrypted at rest using [**SOPS**](https://github.com/getsops/sops) with [**Age**](https://github.com/FiloSottile/age).

### 1. Where to Obtain Public & Private Age Keys

If you already have an Age keypair, your private key file starts with `# created: ...` and `AGE-SECRET-KEY-1...`, and its corresponding public key starts with `age1...`.

To generate a brand-new Age keypair on any machine:

```bash
mkdir -p ~/.config/sops/age
chmod 700 ~/.config/sops/age

# Generate a new private key file
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt

# Print the corresponding public key (recipient)
age-keygen -y ~/.config/sops/age/keys.txt
```

Update [`.sops.yaml`](.sops.yaml) with your **public** key (`age1...`) so SOPS knows which recipient key to encrypt files for. Never commit your private key (`AGE-SECRET-KEY-1...`) to Git; `.gitignore` explicitly excludes `keys.txt`, `*.agekey`, and unencrypted secret files.

### 2. Where to Place the Private Key (Resolution Order)

When `presetup.sh` or `postsetup.sh` runs `ensure_age_key`, it searches for your private Age key in the following order:

1. **`SOPS_AGE_KEY` environment variable**: Direct in-memory private key string (ideal for CI or ephemeral provisioning).
2. **`SOPS_AGE_KEY_FILE` (defaults to `~/.config/sops/age/keys.txt`)**: Standard persistent location with `0600` permissions inside a `0700` directory.
3. **`--age-key-file /path/to/keys.txt` CLI flag (or `AGE_KEY_SOURCE` env var)**: Automatically copies the specified file into `~/.config/sops/age/keys.txt` with `0600` permissions.
4. **`./keys.txt` in the repository root**: If you drop `keys.txt` into the cloned `setupscripts` directory before running `./presetup.sh`, it is automatically installed to `~/.config/sops/age/keys.txt` (`0600`).
5. **Interactive prompt**: In interactive terminals, if no key is found, the script prompts for a path to an existing private key file (or allows pressing `Enter` to continue without SOPS decryption).

### 3. How Automatic Decryption Works

During both `presetup.sh` and `postsetup.sh`, `decrypt_bootstrap_secrets` checks `SECRETS_DIR` (defaults to `./secrets` in the repository root):

| Encrypted Secret File | Decrypted Target | Permissions | Behavior |
| :--- | :--- | :--- | :--- |
| `secrets/id_ed25519.enc` | `~/.ssh/id_ed25519` & `~/.ssh/id_ed25519.pub` | `0600` / `0644` | Restores your Ed25519 private key (if `~/.ssh/id_ed25519` does not already exist) and derives the `.pub` key via `ssh-keygen -y`. |
| `secrets/kubeconfig.enc.yaml` or `secrets/k3s.enc.yaml` | `~/.kube/config` | `0600` | Installs your Kubernetes cluster config and skips remote `k3s` SSH/SCP fetching in `postsetup.sh` (unless `FORCE_K8S_FETCH=1`). |
| `secrets/bootstrap.enc.env` | Exported into shell env | In-memory | Parses `KEY=VALUE` lines (such as `GIT_NAME`, `GIT_EMAIL`, `GH_TOKEN`, `KUBERNETES_IP`) and exports them for the current bootstrap run. |
| `~/projects/homelab/**/*.enc.{yaml,yml,json,env}` or `*.sops.yaml` | Same path without `.enc` / `.sops` | `0600` | During `postsetup.sh`, finds encrypted files up to depth 3 in `homelab` and decrypts each alongside the source file if the target does not yet exist. |

### 4. Encrypting Secrets with SOPS

Because `.sops.yaml` matches paths under `secrets/` (and files matching `*.enc.*` / `*.sops.*`), place or copy the file to its target `.enc` path inside `secrets/` and encrypt it in-place:

```bash
mkdir -p secrets

# 1. Encrypt a Kubernetes config
cp ~/.kube/config secrets/kubeconfig.enc.yaml
sops --encrypt --in-place secrets/kubeconfig.enc.yaml

# 2. Encrypt an SSH private key
cp ~/.ssh/id_ed25519 secrets/id_ed25519.enc
sops --encrypt --in-place secrets/id_ed25519.enc

# 3. Create and encrypt bootstrap environment variables
cat > secrets/bootstrap.enc.env << 'EOF'
GIT_NAME="Your Name"
GIT_EMAIL="you@example.com"
KUBERNETES_IP="192.168.1.31"
KUBERNETES_USER="user"
EOF
sops --encrypt --in-place secrets/bootstrap.enc.env
```

To verify decryption manually at any time:

```bash
sops --decrypt secrets/kubeconfig.enc.yaml
```

---

## Quick Start

1. **Clone the repository:**

   ```bash
   git clone https://github.com/graygarbage/setupscripts.git
   cd setupscripts
   ```

2. **Configure your private Age key:**

   ```bash
   mkdir -p ~/.config/sops/age
   chmod 700 ~/.config/sops/age
   nano ~/.config/sops/age/keys.txt
   chmod 600 ~/.config/sops/age/keys.txt
   ```

3. **Run Stage 1 (`presetup.sh`):**

   ```bash
   ./presetup.sh
   ```

   *(Log out and back in, or allow the reboot prompt, so your user session picks up the `docker` group and updated shell profile.)*

4. **Run Stage 2 (`postsetup.sh`):**

   ```bash
   ./postsetup.sh
   ```

5. **Run Stage 3 (`fix_lazyvim.sh` — optional, for full Neovim/Mason language toolchains):**

   ```bash
   ./fix_lazyvim.sh
   ```

---

## Detailed Execution Flow

### Shared Library (`lib/common.sh`)

Sourced by all three scripts, `lib/common.sh` provides:
- **OS & Architecture Detection**: `detect_os` exports `OS_ID`, `OS_ID_LIKE`, `OS_FAMILY` (`debian`, `fedora`, `arch`, `suse`, `alpine`), `OS_TYPE`, and `PKG_MANAGER` (`apt`, `dnf`, `pacman`, `zypper`, `apk`). `detect_arch` returns `amd64`, `arm64`, or `arm`.
- **Environment Probes**: `is_headless` returns true if `HEADLESS=1` or neither `DISPLAY` nor `WAYLAND_DISPLAY` is set. `is_interactive` returns true only when stdin/stdout are TTYs and `NONINTERACTIVE` is not `1`.
- **Resilient Package Operations**: `wait_for_apt_lock` polls `fuser` on Debian/Ubuntu lock files to prevent failures when unattended-upgrades runs in the background. `update_system_packages`, `install_packages`, and `install_optional_package` abstract package operations across all 5 package managers.
- **Age & SOPS Helpers**: `install_age_and_sops` installs `age` and `sops` (using native packages where available and falling back to the official GitHub release binary for `getsops/sops` matching the system architecture). `ensure_age_key`, `has_age_key`, `sops_decrypt_file`, `sops_extract_value`, and `decrypt_bootstrap_secrets` handle secret lifecycle safely.
- **Idempotency Utilities**: `append_line_if_missing` ensures shell RC files (`~/.bashrc`, `~/.zshrc`, `.envrc`, `options.lua`) never accumulate duplicate lines on repeated runs. `clone_or_update_repo` clones missing repositories or fast-forward pulls (`git pull --ff-only`) existing checkouts.

---

### Stage 1: Pre-Setup (`presetup.sh`)

Executes 16 ordered, idempotent steps:

1. **OS & CPU Architecture Detection**: Calls `detect_os` and `detect_arch`.
2. **System Upgrade**: Refreshes package metadata and upgrades installed system packages (`update_system_packages`).
3. **Core Package Installation**:
   - Installs common tools: `git`, `curl`, `wget`, `zsh`, `neovim`, `vim`, `luarocks`, `cargo`, `imagemagick`, `ca-certificates`, `gnupg`/`gnupg2`/`gpg2`, and basic TeX Live (`texlive-latex-base` / `texlive-scheme-basic` / `texlive-basic`).
   - **Desktop vs. Headless Check**: Installs `alacritty` via `install_optional_package` only when `! is_headless` (`DISPLAY` or `WAYLAND_DISPLAY` present and `HEADLESS != 1`).
4. **Age + SOPS Bootstrap**: Installs `age` and `sops`, resolves the user's private Age key (`ensure_age_key`), and runs `decrypt_bootstrap_secrets`.
5. **Identity Resolution**: Determines `GIT_NAME`, `GIT_EMAIL`, and `SSH_COMMENT` from decrypted secrets, environment variables, existing global Git config, or interactive prompts.
6. **GitHub CLI (`gh`) Setup & Authentication**: Installs `gh` (`install_github_cli`) and verifies `gh auth status`. If unauthenticated, uses `GH_TOKEN`/`GITHUB_TOKEN` if exported, or launches `gh auth login` in interactive sessions.
7. **Tree-sitter CLI Installation**: Adds `~/.cargo/bin` and `~/.local/bin` to `PATH`. Installs `tree-sitter-cli` via native package manager (if available) or compiles via `cargo install tree-sitter-cli`.
8. **Mise Runtime Manager Installation**: Installs [`mise`](https://mise.jdx.dev/) to `~/.local/bin/mise` if not already present.
9. **Shell RC Configuration**: Idempotently appends `PATH` (`$HOME/.local/bin:$HOME/.cargo/bin:$PATH`) and `mise activate` hooks to both `~/.bashrc` and `~/.zshrc`, then activates `mise` in the running Bash process.
10. **SSH Key Generation / Reuse**: Ensures `~/.ssh` exists with `0700` permissions. Reuses `~/.ssh/id_ed25519` (including keys restored from SOPS in Step 4) or `~/.ssh/id_rsa`; otherwise generates a new Ed25519 keypair (`ssh-keygen -t ed25519`).
11. **GitHub SSH Key Upload**: If `gh` is authenticated, checks `gh ssh-key list` for the local public key fingerprint and uploads it via `gh ssh-key add` only if not already registered.
12. **Global Git Configuration**: Sets `git config --global user.name` and `user.email`.
13. **Dotfiles Repository Clone & Setup**: Clones or updates `DOTFILES_REPO` (default `git@github.com:graygarbage/dotfiles.git`) into `~/projects/dotfiles` (unless `SKIP_DOTFILES=1`) and executes `./setup` if present.
14. **Docker Engine & Group Setup**: Installs Docker Engine, CLI, Buildx, and Compose plugins using official repositories on Debian/Ubuntu/Fedora or native packages on Arch/openSUSE/Alpine. Enables and starts `docker.service` via `systemctl` (when systemd is active) and adds `$USER` to the `docker` group (`usermod -aG docker`).
15. **DevPod Installation**: Downloads and installs the latest `devpod-linux-${ARCH}` release binary to `/usr/local/bin/devpod`.
16. **Reboot Handling**: Honours `--no-reboot`, `--reboot`, or prompts interactively whether to reboot immediately.

---

### Stage 2: Post-Setup (`postsetup.sh`)

Run after logging back in or rebooting so the `docker` group and shell environment are active:

1. **Age + SOPS Verification & Secret Decryption**: Ensures `age` and `sops` are present, validates the Age key, and runs `decrypt_bootstrap_secrets` (which can populate `~/.kube/config` and environment variables).
2. **Headless Neovim Tree-sitter Bootstrap**: Runs `nvim --headless -c "TSInstallSync css latex norg scss svelte typst vue" -c "qa"` to compile core syntax parsers without requiring a GUI terminal.
3. **Kubernetes (`k3s`) Kubeconfig Import**:
   - Skipped if `--skip-k8s` is passed, or if `~/.kube/config` already exists (e.g., decrypted from `secrets/kubeconfig.enc.yaml`) and `FORCE_K8S_FETCH` is not `1`.
   - Otherwise prompts for (or reads) `KUBERNETES_IP` (default `192.168.1.31`) and `KUBERNETES_USER` (default `user`). Typing `skip` at the IP prompt skips Kubernetes setup.
   - Copies your SSH public key to the server via `ssh-copy-id`, fetches `k3s.yaml` via `scp`, rewrites the `server:` endpoint to `https://${KUBERNETES_IP}:6443`, and installs it to `~/.kube/config` with `0600` permissions.
4. **Homelab Repository & DevPod Workspace Initialization** (unless `SKIP_HOMELAB=1`):
   - Clones or updates `HOMELAB_REPO` (default `git@github.com:graygarbage/homelab.git`) into `~/projects/homelab`.
   - Decrypts any `*.enc.{yaml,yml,json,env}` and `*.sops.yaml` files inside `~/projects/homelab` when an Age key is present.
   - Runs `mise trust && mise install` inside `~/projects/homelab`.
   - Appends `export KUBECONFIG=/workspaces/homelab/kubeconfig` to `~/projects/homelab/.envrc` and copies `~/.kube/config` to `~/projects/homelab/kubeconfig` (`0600`).
   - Unless `--skip-devpod` is set, ensures the DevPod `docker` provider is registered (`devpod provider add docker`) and starts the workspace headless via `devpod up . --ide none --dotfiles "$DOTFILES_REPO"`.
5. **Chezmoi Dotfiles Sync**: If `chezmoi` is installed and `~/.local/share/chezmoi` is initialized, runs `chezmoi update`.
6. **LazyVim Plugin Sync**: Synchronizes Neovim plugins headlessly via `nvim --headless "+Lazy! sync" +qa`, and opens interactive `nvim` only if `--open-nvim` was specified in an interactive terminal.

---

### Stage 3: LazyVim & Mason Toolchains (`fix_lazyvim.sh`)

Resolves `:checkhealth` warnings in LazyVim and installs compilers/providers required by Mason language servers:

1. **Multi-Distro Language Toolchains**: Installs Go (`golang`/`go`), Rust (`rustc`/`rust`, `cargo`), Ruby (`ruby-full`/`ruby`), PHP (`php-cli`/`php`/`php8`/`php83`), Java SDK (`default-jdk`/`java-latest-openjdk-devel`/`jdk-openjdk`/`openjdk21`), Node.js & NPM (`nodejs`, `npm`), Perl & `cpanm` (`cpanminus`/`perl-App-cpanminus`), SQLite3 CLI & C headers (`sqlite3` + `libsqlite3-dev`/`sqlite-devel`), LaTeX build tool (`latexmk`/`texlive-binextra`), plus optional `julia` and `tectonic` where available in distro repos.
2. **Rootless NPM Global Prefix & Providers**: Configures NPM to install global packages under `~/.local/share/npm-global` (preventing `EACCES` permission errors without `sudo npm`) and installs `@mermaid-js/mermaid-cli` (`mmdc`) and the `neovim` Node.js host provider.
3. **Perl Neovim Provider**: Installs `Neovim::Ext` into `~/perl5` using `cpanm --local-lib="${HOME}/perl5" --notest Neovim::Ext`.
4. **Shell Environment Persistence**: Idempotently configures `PERL5LIB="$HOME/perl5/lib/perl5${PERL5LIB:+:$PERL5LIB}"` and adds `$HOME/.local/share/npm-global/bin`, `$HOME/perl5/bin`, `$HOME/.local/bin`, `$HOME/.cargo/bin` (and `/usr/local/go/bin` if present) to `PATH` in `~/.bashrc` and `~/.zshrc`.
5. **Neovim Terminal Handler Configuration**: Safely sets `vim.g.termui_handler = "wezterm"` in `~/.config/nvim/lua/config/options.lua` (or `let g:termui_handler = "wezterm"` if using a legacy `~/.config/nvim/init.vim`), avoiding any conflicting `init.vim` alongside `init.lua`.

---

## CLI Flags & Environment Variables

### Command-Line Flags

#### `./presetup.sh`

| Flag | Description |
| :--- | :--- |
| `--no-reboot` | Do not reboot or prompt to reboot when `presetup.sh` finishes. |
| `--reboot` | Automatically reboot 10 seconds after `presetup.sh` finishes. |
| `--age-key-file PATH` | Copy the specified private Age key file to `~/.config/sops/age/keys.txt` (`0600`). |
| `--non-interactive` | Run unattended without interactive prompts (`NONINTERACTIVE=1`). |
| `-h`, `--help` | Display usage help and exit. |

#### `./postsetup.sh`

| Flag | Description |
| :--- | :--- |
| `--skip-k8s` | Skip remote Kubernetes (`k3s`) SSH key copy and `k3s.yaml` SCP fetch. |
| `--skip-devpod` | Skip DevPod provider registration and `devpod up` workspace creation. |
| `--open-nvim` | Launch interactive Neovim at the end of `postsetup.sh` (interactive sessions only). |
| `--age-key-file PATH` | Copy the specified private Age key file to `~/.config/sops/age/keys.txt` (`0600`). |
| `--non-interactive` | Run unattended without interactive prompts (`NONINTERACTIVE=1`). |
| `-h`, `--help` | Display usage help and exit. |

#### `./fix_lazyvim.sh`

| Flag | Description |
| :--- | :--- |
| `--skip-update` | Skip the initial system package repository refresh/upgrade step. |
| `--non-interactive` | Run unattended without interactive prompts (`NONINTERACTIVE=1`). |
| `-h`, `--help` | Display usage help and exit. |

---

### Environment Variables

| Variable | Default | Used By | Description |
| :--- | :--- | :--- | :--- |
| `SOPS_AGE_KEY` | *(unset)* | All | Raw private Age key string (`AGE-SECRET-KEY-1...`) for in-memory SOPS decryption. |
| `SOPS_AGE_KEY_FILE` | `~/.config/sops/age/keys.txt` | All | Path to private Age key file used by SOPS. |
| `AGE_KEY_SOURCE` | *(unset)* | `presetup.sh`, `postsetup.sh` | Source path of an Age private key file to install into `SOPS_AGE_KEY_FILE`. |
| `SECRETS_DIR` | `./secrets` | `presetup.sh`, `postsetup.sh` | Directory containing SOPS-encrypted bootstrap secrets (`id_ed25519.enc`, `kubeconfig.enc.yaml`, `bootstrap.enc.env`). |
| `SOPS_VERSION` | Latest release (`v3.9.4` fallback) | `lib/common.sh` | Version tag used if SOPS binary fallback download from GitHub Releases is needed. |
| `NONINTERACTIVE` | `0` | All | Set to `1` to disable all interactive `read` prompts and use defaults/env vars. |
| `HEADLESS` | Auto-detected via `DISPLAY`/`WAYLAND_DISPLAY` | `presetup.sh` | Set to `1` to force headless mode (skips GUI apps such as `alacritty`). |
| `GIT_NAME` | Existing `user.name` or `graygarbage` | `presetup.sh` | Global Git `user.name`. |
| `GIT_EMAIL` | Existing `user.email` | `presetup.sh` | Global Git `user.email`. |
| `SSH_KEY_PATH` | `~/.ssh/id_ed25519` | `presetup.sh` | Path for SSH private key generation/lookup. |
| `SSH_COMMENT` | `${GIT_EMAIL}` or `${USER}@$(hostname -s)` | `presetup.sh` | Comment embedded in newly generated SSH keys. |
| `SSH_COMMENT_SET` | *(unset)* | `presetup.sh` | Set to `1` to suppress the interactive SSH comment prompt even in interactive mode. |
| `SSH_PASSPHRASE` | `""` (empty) | `presetup.sh` | Passphrase for newly generated SSH key in non-interactive runs. |
| `SSH_KEY_TITLE` | `Linux-<hostname>-<YYYYMMDD>` | `presetup.sh` | Title used when registering the SSH public key on GitHub via `gh ssh-key add`. |
| `GH_TOKEN` / `GITHUB_TOKEN` | *(unset)* | `presetup.sh` | GitHub personal access token for non-interactive `gh` CLI authentication. |
| `DOTFILES_REPO` | `git@github.com:graygarbage/dotfiles.git` | `presetup.sh`, `postsetup.sh` | Git URL for dotfiles repository and DevPod `--dotfiles` parameter. |
| `DOTFILES_DIR` | `~/projects/dotfiles` | `presetup.sh` | Local checkout directory for dotfiles. |
| `SKIP_DOTFILES` | `0` | `presetup.sh` | Set to `1` to skip cloning and running the dotfiles repository setup. |
| `HOMELAB_REPO` | `git@github.com:graygarbage/homelab.git` | `postsetup.sh` | Git URL for homelab repository. |
| `HOMELAB_DIR` | `~/projects/homelab` | `postsetup.sh` | Local checkout directory for homelab. |
| `SKIP_HOMELAB` | `0` | `postsetup.sh` | Set to `1` to skip homelab clone, secret decryption, Mise install, and DevPod startup. |
| `KUBERNETES_IP` | `192.168.1.31` | `postsetup.sh` | Remote `k3s` server IP address for `ssh-copy-id` and `scp`. |
| `KUBERNETES_USER` | `user` | `postsetup.sh` | Remote `k3s` server SSH username. |
| `KUBERNETES_REMOTE_PATH` | `/home/${KUBERNETES_USER}/k3s.yaml` | `postsetup.sh` | Remote path to `k3s.yaml` on the Kubernetes server. |
| `FORCE_K8S_FETCH` | `0` | `postsetup.sh` | Set to `1` to force remote `k3s.yaml` SCP fetch even if `~/.kube/config` already exists. |

---

## Usage Recipes (Desktop, Headless, Unattended)

### 1. Interactive Desktop Workstation Setup

On a fresh Fedora, Ubuntu/Debian, or Arch desktop with GUI (`DISPLAY` or `WAYLAND_DISPLAY` active):

```bash
./presetup.sh --age-key-file ~/Downloads/keys.txt
# Reboot when prompted (or log out and back in)
./postsetup.sh --open-nvim
./fix_lazyvim.sh
```

### 2. Headless Server or VM Setup (No GUI, No Automatic Reboot)

When connected over SSH to a headless server:

```bash
HEADLESS=1 ./presetup.sh --no-reboot
# Log out and reconnect over SSH (or run `newgrp docker`) to activate docker group
./postsetup.sh --skip-devpod
```

### 3. Fully Unattended / Non-Interactive Provisioning

For automated provisioning, cloud-init, or CI environments:

```bash
export NONINTERACTIVE=1
export HEADLESS=1
export SOPS_AGE_KEY="AGE-SECRET-KEY-1..."
export GH_TOKEN="ghp_your_github_token"
export GIT_NAME="graygarbage"
export GIT_EMAIL="you@example.com"

./presetup.sh --non-interactive --no-reboot
sg docker -c "./postsetup.sh --non-interactive --skip-k8s"
./fix_lazyvim.sh --non-interactive --skip-update
```

---

## Troubleshooting Guide

### Stage 0: Age & SOPS Decryption

- **`Failed to decrypt ... with SOPS` or `no identity matched any of the recipients`**
  - Verify your local private key matches the public recipient key used to encrypt the file:
    ```bash
    age-keygen -y ~/.config/sops/age/keys.txt
    ```
  - Compare the printed `age1...` public key against the `age:` recipient list in `.sops.yaml` and the `sops.age` metadata block at the bottom of the encrypted file.
- **`sops --encrypt` fails with `config file not found` or `no matching creation rules`**
  - Ensure you run `sops` from the repository root (where `.sops.yaml` resides) and that the target file path is inside `secrets/` or ends with `.enc.{yaml,yml,json,env,txt,key}` (for example, `cp ~/.kube/config secrets/kubeconfig.enc.yaml && sops --encrypt --in-place secrets/kubeconfig.enc.yaml`).
- **Permissions warning on `~/.config/sops/age/keys.txt`**
  - Fix directory and key permissions:
    ```bash
    chmod 700 ~/.config/sops/age
    chmod 600 ~/.config/sops/age/keys.txt
    ```

### Stage 1: `presetup.sh`

- **APT/DPKG lock contention on Ubuntu/Debian (`Waiting for APT/DPKG lock to be released...`)**
  - Fresh Ubuntu/Debian installs often run `unattended-upgrades` on first boot. `wait_for_apt_lock` automatically waits for `/var/lib/dpkg/lock-frontend` to clear. If it hangs indefinitely, check `ps aux | grep -E 'apt|dpkg'` to see if another terminal has an open `apt` process.
- **GitHub SSH clone fails for `dotfiles` (`Permission denied (publickey)`)**
  - Ensure `gh auth status` succeeded in Step 6 so Step 11 could upload `~/.ssh/id_ed25519.pub` to GitHub, or provide an encrypted key at `secrets/id_ed25519.enc`.
  - If you want to use an HTTPS URL or your own fork instead, run:
    ```bash
    DOTFILES_REPO="https://github.com/youruser/dotfiles.git" ./presetup.sh
    ```
    or skip dotfiles entirely with `SKIP_DOTFILES=1 ./presetup.sh`.
- **`cargo install tree-sitter-cli` takes several minutes or fails on low-memory VMs**
  - On distros where `tree-sitter-cli` is not in the default package repositories, Cargo compiles it from source. Ensure at least 2 GB of RAM/swap is available, or pre-install `tree-sitter-cli` via `mise` (`mise use -g tree-sitter`) before re-running `./presetup.sh`.

### Stage 2: `postsetup.sh`

- **Docker permission denied during `devpod up` (`permission denied while trying to connect to the Docker daemon socket`)**
  - `presetup.sh` adds `$USER` to the `docker` group, but Linux group membership only takes effect on a new login session. Log out and log back in, reboot, or run `newgrp docker` before running `./postsetup.sh`.
  - Also verify the daemon is running: `sudo systemctl status docker`.
- **Remote `k3s` kubeconfig fetch fails or hangs on `ssh-copy-id` / `scp`**
  - Verify the remote `k3s` node is reachable (`ping $KUBERNETES_IP`) and that `KUBERNETES_USER` has read access to `/home/${KUBERNETES_USER}/k3s.yaml`.
  - To skip remote fetching on networks without the `k3s` node, pass `--skip-k8s` (or type `skip` when prompted for the IP).
  - To overwrite an existing `~/.kube/config` with a fresh copy from the remote server, run:
    ```bash
    FORCE_K8S_FETCH=1 ./postsetup.sh
    ```
- **Headless Neovim Tree-sitter parser compilation warning**
  - If Neovim plugins have not yet been bootstrapped by LazyVim on first run, `TSInstallSync` may warn and exit non-zero before Step 6 runs `+Lazy! sync`. Re-running `./postsetup.sh` after Step 6 completes will cleanly compile any remaining parsers.

### Stage 3: `fix_lazyvim.sh`

- **`:checkhealth` in Neovim still reports missing `neovim` Node.js or `Neovim::Ext` Perl provider**
  - Reload your shell configuration so the updated `PATH` (`~/.local/share/npm-global/bin` and `~/perl5/bin`) and `PERL5LIB` (`~/perl5/lib/perl5`) take effect:
    ```bash
    source ~/.bashrc   # or: source ~/.zshrc
    ```
  - Then verify inside Neovim:
    ```bash
    nvim --headless -c "checkhealth vim.provider" -c "qa"
    ```
- **Conflicting `init.lua` and `init.vim` warning in `:checkhealth`**
  - `fix_lazyvim.sh` writes `vim.g.termui_handler = "wezterm"` to `~/.config/nvim/lua/config/options.lua` when `init.lua` is used. If an older manual setup created `~/.config/nvim/init.vim` alongside `init.lua`, remove or merge the stray `~/.config/nvim/init.vim`.

---

## License

This project is licensed under the MIT License - see the [LICENSE](license) file for details.
