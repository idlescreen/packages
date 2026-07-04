# UberMetroid RPM Repository

This repository hosts compiled RPM distributions for the **UberMetroid** ecosystem (specifically **trance**). It functions as a flat RPM package repository served directly via GitHub Pages raw file endpoints.

Supported formats:
*   **RPM** (Fedora, RHEL, CentOS)

---

## Client Installation & Setup

1.  **Configure the DNF repository:**
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

2.  **Update the package database:**
    ```bash
    sudo dnf check-update
    ```
