# Setup Scripts

## Overview

These scripts automate the setup of a new Linux machine, including package installations, configuration of Git, SSH keys, Docker, DevPod, and Kubernetes integration.

## Prerequisites

- Linux distribution (Ubuntu/Debian-based or Arch-based).
- Internet connection.
- Sudo privileges.

## Usage

1. **Clone the repository:**

    ```bash
    git clone https://github.com/yourusername/setup-scripts.git
    cd setup-scripts
    ```

2. **Run the prescript:**

    ```bash
    chmod +x pre-setup.sh
    ./pre-setup.sh
    ```

3. **Reboot the machine:**

    The script will automatically reboot the machine to apply changes.

4. **Run the postscript after reboot:**

    ```bash
    chmod +x post-setup.sh
    ./post-setup.sh
    ```

## Configuration

- **SSH Key Comment:** Modify the comment in `pre-setup.sh` if needed.
- **Kubernetes Server IP:** Update the IP address in `post-setup.sh` to match your Kubernetes server.

## Contributing

Feel free to contribute by opening issues or pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE](license) file for details.
