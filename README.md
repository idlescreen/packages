# UberMetroid Packages Repository

This repository serves as the central distribution hub for the **UberMetroid** ecosystem applications (such as `trance`, `beam`, `todo`, etc.). It supports distribution across multiple package managers and environments.

Supported formats:
*   **APT** (Debian, Ubuntu, Pop!_OS) — hosted under `/apt` and served via GitHub Pages
*   **Nix Flakes** (NixOS, Unraid Nix Plugin) — defined at the root (`flake.nix`)

---

## 1. Debian / Ubuntu Setup (APT)

To install compiled Debian packages (such as `trance`):

### Automated Installation (Recommended)
```bash
curl -fsSL https://ubermetroid.github.io/packages/apt/install.sh | sudo bash
sudo apt install trance
```

For manual installation instructions and GPG keyring details, see the [APT Readme](apt/README.md).

---

## 2. NixOS / Unraid Nix Setup (Flakes)

To run or build applications directly using Nix Flakes:

### Run directly
```bash
nix run github:UberMetroid/packages#trance
```

### Import into configurations
Add the repository to your flake inputs:
```nix
inputs = {
  ubermetroid-packages.url = "github:UberMetroid/packages";
};
```
