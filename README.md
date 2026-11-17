# Setup Scripts

## Overview

Resilient, idempotent bootstrapping scripts to provision and configure a Linux workstation or server across multiple Linux distribution families:
- **Fedora / RHEL family** (`dnf`: Fedora, RHEL, CentOS Stream, Rocky, AlmaLinux, Nobara)
- **Ubuntu / Debian family** (`apt`: Ubuntu, Debian, Pop!_OS, Linux Mint, Raspbian)
- **Arch Linux family** (`pacman`: Arch, Manjaro, EndeavourOS, CachyOS)
- **openSUSE & Alpine** (`zypper`, `apk`)

Supports both **desktop/GUI** and **headless/server** environments across `x86_64` (`amd64`) and `aarch64` (`arm64`) architectures, with native **Age + SOPS** secret management.

## Prerequisites

- Supported Linux distribution (Fedora, Ubuntu, Debian, Arch, openSUSE, or Alpine).
- Internet connection and `sudo` privileges.
- *(Optional)* Your private **Age key** for decrypting SOPS-managed secrets (`~/.config/sops/age/keys.txt`).

## Quick Start (Age + SOPS Bootstrap Workflow)

1. **Clone the repository:**

    ```bash
    git clone https://github.com/graygarbage/setupscripts.git
    cd setupscripts
    ```

2. **Place your private Age key (for SOPS secret decryption):**

    ```bash
    mkdir -p ~/.config/sops/age
    chmod 700 ~/.config/sops/age
    # Copy or paste your private Age key into ~/.config/sops/age/keys.txt
    nano ~/.config/sops/age/keys.txt
    chmod 600 ~/.config/sops/age/keys.txt
    ```

    *(Alternatively, pass `--age-key-file /path/to/keys.txt` or export `SOPS_AGE_KEY` / `SOPS_AGE_KEY_FILE`.)*

3. **Run the pre-setup script:**

    ```bash
    ./presetup.sh
    ```

    Use `./presetup.sh --no-reboot` to skip the reboot prompt on headless servers or containers.

4. **Run the post-setup script (after re-login or reboot):**

    ```bash
    ./postsetup.sh
    ```

5. **Optional — Install LazyVim / Mason language toolchains and providers:**

    ```bash
    ./fix_lazyvim.sh
    ```

## Age & SOPS Secret Management

All encrypted secrets use **SOPS** with an **Age** keypair:
- `age` and `sops` are automatically installed across Fedora, Ubuntu, Debian, and Arch.
- Public Age recipient keys are configured in [`.sops.yaml`](.sops.yaml).
- Encrypted files placed under `secrets/` (such as `secrets/id_ed25519.enc`, `secrets/kubeconfig.enc.yaml`, or `secrets/bootstrap.enc.env`) and `*.enc.*` files inside your `homelab` repository are automatically decrypted when your private Age key is present.

### Encrypting a Secret

```bash
# Encrypt a kubeconfig or environment file using the public Age key in .sops.yaml
sops --encrypt ~/.kube/config > secrets/kubeconfig.enc.yaml
```

## Customization & Environment Variables

All scripts are re-entrant (idempotent) and can be customized via flags or environment variables:

| Variable | Description | Default |
| :--- | :--- | :--- |
| `GIT_NAME` | Global Git `user.name` | Prompted / existing config |
| `GIT_EMAIL` | Global Git `user.email` | Prompted / existing config |
| `DOTFILES_REPO` | Git URL for dotfiles repo (`SKIP_DOTFILES=1` to skip) | `git@github.com:graygarbage/dotfiles.git` |
| `HOMELAB_REPO` | Git URL for homelab repo (`SKIP_HOMELAB=1` to skip) | `git@github.com:graygarbage/homelab.git` |
| `SOPS_AGE_KEY_FILE` | Path to private Age key file | `~/.config/sops/age/keys.txt` |
| `KUBERNETES_IP` | Remote k3s server IP (`--skip-k8s` to skip) | `192.168.1.31` |
| `KUBERNETES_USER` | Remote k3s SSH username | `user` |
| `NONINTERACTIVE` | Set to `1` (or pass `--non-interactive`) for unattended runs | `0` |

## License

This project is licensed under the MIT License - see the [LICENSE](license) file for details.
