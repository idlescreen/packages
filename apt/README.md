# crateria APT Repository

This repository hosts compiled Debian distributions for the **crateria** ecosystem (specifically **trance**). It functions as a flat package repository served directly via GitHub Pages raw file endpoints.

Supported formats:
*   **APT** (Debian, Ubuntu, Pop!_OS)

---

## Client Installation & Setup

1.  **Import the repository GPG key** into a dedicated keyring (do **not** use `/etc/apt/trusted.gpg.d/` unless you accept global trust):
    ```bash
    sudo mkdir -p /etc/apt/keyrings
    sudo curl -fsSL https://crateria.github.io/packages/apt/crateria-keyring.gpg \
      -o /etc/apt/keyrings/crateria.gpg
    ```

2.  **Add the repository entry** (matches `crateria.list` in this tree):
    ```bash
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/crateria.gpg] https://crateria.github.io/packages/apt stable main" \
      | sudo tee /etc/apt/sources.list.d/crateria.list
    ```

3.  **Update the package index:**
    ```bash
    sudo apt update
    ```
