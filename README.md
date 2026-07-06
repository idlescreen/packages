# packages — Official APT & DNF Package Repositories

Official Debian (APT) and Fedora (DNF) package repositories hosting native desktop package builds for UberMetroid applications.

---

## 🏛️ Architecture & Stack
*   **Format**: APT (.deb) / DNF (.rpm) package indexes
*   **Hosting**: GitHub Pages
*   **Target**: Debian, Ubuntu, Pop!_OS, Fedora, RHEL, CentOS

---

## 🟢 Key Features
*   **Automated Hosting**: Packages served securely directly from GitHub Pages.
*   **Standard Signatures**: Complete GPG signing verification configurations.
*   **Native Updates**: Straightforward integration with default system package managers.

---

## 💾 Deployment & Installation

### Debian / Ubuntu / Pop!_OS Setup (APT)

```bash
# 1. Download the repository GPG keyring
sudo curl -fsSL https://ubermetroid.github.io/packages/apt/ubermetroid-keyring.gpg -o /etc/apt/trusted.gpg.d/ubermetroid.gpg

# 2. Download the sources list configuration
sudo curl -fsSL https://ubermetroid.github.io/packages/apt/ubermetroid.list -o /etc/apt/sources.list.d/ubermetroid.list

# 3. Refresh the package index
sudo apt update
```

### Fedora / RHEL / CentOS Setup (DNF)

```bash
# 1. Download the repository configuration
sudo curl -fsSL https://ubermetroid.github.io/packages/rpm/ubermetroid.repo -o /etc/yum.repos.d/ubermetroid.repo

# 2. Refresh the package database
sudo dnf check-update
```

---

## 📄 License
Licensed under the [Apache License, Version 2.0](LICENSE). Copyright 2026 UberMetroid.
