# Crateria packages

<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="Crateria">
</p>

<p align="center">
  <strong>APT + DNF</strong> package repositories for
  <a href="https://github.com/crateria">Crateria</a> desktop apps
</p>

Hosted on GitHub Pages: **[crateria.github.io/packages](https://crateria.github.io/packages/)**

Ships native builds for **trance**, **trance-plugins**, **morphball**, and related packages.

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
sudo apt install trance   # or: morphball
```

Or install the committed `apt/crateria.list` after placing the keyring as above.

### Fedora / RHEL (DNF)

```bash
sudo curl -fsSL https://crateria.github.io/packages/rpm/crateria.repo \
  -o /etc/yum.repos.d/crateria.repo
sudo dnf check-update
sudo dnf install trance   # or: morphball
```

The repo enables `gpgcheck=1` (each RPM is signed). Metadata is served over HTTPS; `repo_gpgcheck` is off so plain `dnf update` works without a stuck key prompt.

---

## Architecture

| | |
|--|--|
| Formats | APT (`.deb`) / DNF (`.rpm`) |
| Hosting | GitHub Pages |
| Targets | Debian, Ubuntu, Pop!_OS, Fedora, RHEL-compatible |
| Brand | Icons from [crateria/brand](https://github.com/crateria/brand) |

---

## Maintainer notes

See also `apt/MAINTAINER.md` and [docs/SIGNING.md](docs/SIGNING.md).

| Topic | Guidance |
| :--- | :--- |
| **Build packages** | From `trance/`: `./package.rs` (or `cargo deb` / `cargo generate-rpm` per crate); plugins from `trance-plugins/package.rs` |
| **Index + sign** | From this repo: `./update.sh` — must have GPG secret key; do **not** publish unsigned indexes |
| **RPM packages** | Run `./sign_all.sh` with `CRATERIA_GPG_NAME` set (see [docs/SIGNING.md](docs/SIGNING.md)) |
| **Prune pool** | `./scripts/prune.sh` keeps latest N versions (default 3) |
| **Version alignment** | Crate version in `trance-daemon` (and tags `vX.Y.Z`) should match published `trance_X.Y.Z-1_amd64.deb` |
| **Plugins** | `trance-plugins-all` recommends all optional savers including **radar**; beams ships as hard depends of core `trance` |

### Operational risks

* Skipping GPG when the key is missing previously only **warned** — treat that as a failed release.
* APT `Packages` index can list many historical versions; prune regularly to limit download of stale metadata.
* Hosted debs lag git `main` until you rebuild and re-run `update.sh`.

---

## Links

| | |
|--|--|
| Org | [crateria](https://github.com/crateria) |
| Brand kit | [brand](https://github.com/crateria/brand) |
| Products | [trance](https://github.com/crateria/trance) · [morphball](https://github.com/crateria/morphball) |
| Security | [SECURITY.md](SECURITY.md) |

## License

[Apache-2.0](LICENSE) · Copyright 2026 [Crateria](https://github.com/crateria)
