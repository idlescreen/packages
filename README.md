<p align="center">
  <a href="https://github.com/crateria">
    <img src="assets/crateria-header.jpg" alt="Crateria" width="100%">
  </a>
</p>

# Crateria packages

APT and DNF repositories for Crateria desktop applications.

**Site:** [crateria.github.io/packages](https://crateria.github.io/packages/)

## Install (users)

### Debian / Ubuntu / Pop!_OS

Use a dedicated keyring and `signed-by` (avoid dropping the key into
`/etc/apt/trusted.gpg.d/` unless you intend global trust):

```bash
sudo mkdir -p /etc/apt/keyrings
sudo curl -fsSL https://crateria.github.io/packages/apt/crateria-keyring.gpg \
  -o /etc/apt/keyrings/crateria.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/crateria.gpg] https://crateria.github.io/packages/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/crateria.list
sudo apt update
sudo apt install trance   # or: morphball
```

### Fedora / RHEL-compatible

```bash
sudo curl -fsSL https://crateria.github.io/packages/rpm/crateria.repo \
  -o /etc/yum.repos.d/crateria.repo
sudo dnf install trance   # or: morphball
```

RPM packages are signed (`gpgcheck=1`). Metadata is served over HTTPS.

## Repository layout

| Path | Content |
|------|---------|
| `apt/` | Debian package pool and indexes |
| `rpm/` | RPM pool and repodata |
| `assets/` | Header banner and site favicon |
| `docs/SIGNING.md` | Maintainer signing procedure |
| `src/` | Index update and prune tools |

## Maintainer workflow

| Step | Command / notes |
|------|-----------------|
| Build product packages | From product repos (`trance`, `trance-plugins`, `morphball`) |
| Sign RPMs and refresh metadata | `CRATERIA_GPG_NAME=… ./sign_all.sh` (see [docs/SIGNING.md](docs/SIGNING.md)) |
| Metadata only | `./update.sh` |
| Prune old versions | `./scripts/prune.sh` (default: keep latest 3) |

Do not publish unsigned indexes. Do not commit private keys.

Further detail: `apt/MAINTAINER.md`.

## Links

| Resource | URL |
|----------|-----|
| Organization | [github.com/crateria](https://github.com/crateria) |
| Brand kit | [crateria/brand](https://github.com/crateria/brand) |
| Security | [SECURITY.md](SECURITY.md) |

## License

[Apache-2.0](LICENSE) · Copyright 2026 Crateria
