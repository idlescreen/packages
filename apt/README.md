# UberMetroid APT Repository

This repository hosts compiled Debian distributions for the **UberMetroid** ecosystem (specifically **trance**). It functions as a flat package repository served directly via GitHub Pages raw file endpoints.

Supported formats:
*   **APT** (Debian, Ubuntu, Pop!_OS)

---

## Client Installation & Setup

1.  **Import the repository GPG key:**
    ```bash
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://ubermetroid.github.io/packages/apt/ubermetroid-key.gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/ubermetroid-keyring.gpg
    ```

2.  **Add the repository entry:**
    ```bash
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/ubermetroid-keyring.gpg] https://ubermetroid.github.io/packages/apt stable main" | sudo tee /etc/apt/sources.list.d/ubermetroid.list
    ```

3.  **Update the package index:**
    ```bash
    sudo apt update
    ```
