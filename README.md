# UberMetroid Packages

APT package repository for **UberMetroid** applications (such as `trance`).

## Installation Setup

To register the repository and install packages:

1. **Import the repository GPG key:**
   ```bash
   sudo mkdir -p /etc/apt/keyrings
   curl -fsSL https://ubermetroid.github.io/packages/apt/ubermetroid-key.gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/ubermetroid-keyring.gpg
   ```

2. **Register the APT source:**
   ```bash
   echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/ubermetroid-keyring.gpg] https://ubermetroid.github.io/packages/apt stable main" | sudo tee /etc/apt/sources.list.d/ubermetroid.list
   ```

3. **Update the package index:**
   ```bash
   sudo apt update
   ```

---

*For repository maintenance, pruning, and indexing instructions, see the [Maintainer Guide](apt/MAINTAINER.md).*
