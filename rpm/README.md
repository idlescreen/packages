# crateria RPM Repository

This repository hosts compiled RPM distributions for the **crateria** ecosystem (specifically **trance**). It functions as a flat RPM package repository served directly via GitHub Pages raw file endpoints.

Supported formats:
*   **RPM** (Fedora, RHEL, CentOS)

---

## Client Installation & Setup

```bash
# 1. Download the repository configuration
sudo curl -fsSL https://crateria.github.io/packages/rpm/crateria.repo -o /etc/yum.repos.d/crateria.repo

# 2. Refresh the package database
sudo dnf check-update
```
