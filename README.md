# UberMetroid Packages

Package repository for **UberMetroid** applications (such as `trance`).

## Debian / Ubuntu / Pop!_OS Setup (APT)

1. **Import the GPG key:**
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

## Fedora / RHEL / CentOS Setup (DNF)

1. **Add the DNF repository configuration:**
   ```bash
   sudo tee /etc/yum.repos.d/ubermetroid.repo << 'EOF'
[ubermetroid]
name=UberMetroid RPM Repository
baseurl=https://ubermetroid.github.io/packages/rpm
enabled=1
gpgcheck=1
gpgkey=https://ubermetroid.github.io/packages/rpm/ubermetroid-key.gpg
EOF
   ```

2. **Update the package database:**
   ```bash
   sudo dnf check-update
   ```

---

*For repository maintenance, pruning, and indexing instructions, see the [Maintainer Guide](apt/MAINTAINER.md).*
