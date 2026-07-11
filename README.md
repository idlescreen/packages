# packages — Official APT & DNF Package Repositories

Official Debian (APT) and Fedora (DNF) package repositories hosting native desktop package builds for crateria applications (primarily **trance** and **trance-plugins**).

---

## Architecture & Stack
*   **Format**: APT (`.deb`) / DNF (`.rpm`) package indexes
*   **Hosting**: GitHub Pages (`crateria.github.io/packages`)
*   **Targets**: Debian, Ubuntu, Pop!_OS, Fedora, RHEL-compatible

---

## Client install

### Debian / Ubuntu / Pop!_OS (APT)

Prefer a **dedicated keyring** + `signed-by` (do **not** drop the key into `/etc/apt/trusted.gpg.d/` unless you accept global trust):

```bash
sudo mkdir -p /etc/apt/keyrings
sudo curl -fsSL https://crateria.github.io/packages/apt/crateria-keyring.gpg \
  -o /etc/apt/keyrings/crateria.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/crateria.gpg] https://crateria.github.io/packages/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/crateria.list
sudo apt update
sudo apt install trance
```

Or install the committed `apt/crateria.list` after placing the keyring as above.

### Fedora / RHEL (DNF)

```bash
sudo curl -fsSL https://crateria.github.io/packages/rpm/crateria.repo \
  -o /etc/yum.repos.d/crateria.repo
sudo dnf check-update
sudo dnf install trance
```

The repo enables `gpgcheck=1` (each RPM is signed). Metadata is served over HTTPS; `repo_gpgcheck` is off so plain `dnf update` works without a stuck key prompt.

---

## Maintainer notes (hygiene)

See also `apt/MAINTAINER.md`.

| Topic | Guidance |
| :--- | :--- |
| **Build packages** | From `trance/`: `./package.rs` (or `cargo deb` / `cargo generate-rpm` per crate); plugins from `trance-plugins/package.rs` |
| **Index + sign** | From this repo: `./update.sh` — must have GPG secret key; do **not** publish unsigned indexes |
| **RPM packages** | Run `./sign_all.sh` so individual RPMs verify under `gpgcheck=1` |
| **Prune pool** | `./scripts/prune.sh` keeps latest N versions (default 3) |
| **Version alignment** | Crate version in `trance-daemon` (and tags `vX.Y.Z`) should match published `trance_X.Y.Z-1_amd64.deb` |
| **Plugins** | `trance-plugins-all` recommends all optional savers including **radar**; beams ships as hard depends of core `trance` |

### Known operational risks
* Skipping GPG when the key is missing previously only **warned** — treat that as a failed release.
* APT `Packages` index can list many historical versions; prune regularly to limit download of stale metadata.
* Hosted debs lag git `main` until you rebuild and re-run `update.sh`.

---

## License
Licensed under the [Apache License, Version 2.0](LICENSE). Copyright 2026 crateria.
