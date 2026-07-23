# IdleScreen packages

[![CI](https://github.com/idlescreen/packages/actions/workflows/ci.yml/badge.svg)](https://github.com/idlescreen/packages/actions/workflows/ci.yml)
[![Pages](https://img.shields.io/badge/index-idlescreen.github.io%2Fpackages-orange)](https://idlescreen.github.io/packages/)

Signed APT (`.deb`) and DNF (`.rpm`) repositories for **IdleScreen**.

| | |
|---|---|
| Public index | [idlescreen.github.io/packages](https://idlescreen.github.io/packages/) |
| Brand | [idlescreen/brand](https://github.com/idlescreen/brand) |
| Host | `idlescreen.github.io` |
| Org | [idlescreen](https://github.com/idlescreen) |

Server asset filenames and some env vars may still use a historical
`crateria-*` / `CRATERIA_*` prefix for compatibility. The public host and brand
are IdleScreen. Shipped application package names remain `trance` / `trance-*`.

## User install

### Debian / Ubuntu / Pop!_OS

```bash
sudo mkdir -p /etc/apt/keyrings
sudo curl -fsSL https://idlescreen.github.io/packages/apt/crateria-keyring.gpg \
  -o /etc/apt/keyrings/idlescreen.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/idlescreen.gpg] https://idlescreen.github.io/packages/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/idlescreen.list
sudo apt update
sudo apt install trance
```

### Fedora

```bash
sudo curl -fsSL https://idlescreen.github.io/packages/rpm/crateria.repo \
  -o /etc/yum.repos.d/idlescreen.repo
sudo dnf install trance
```

Optional packages: `trance-plugin-*`, meta package `trance-plugins-all`.

## Release to index pipeline

1. Product repo tags `vX.Y.Z` and publishes `.deb` / `.rpm` assets.
2. Product Release workflow may send `repository_dispatch` type `new_release` here
   (product secret: `IDLESCREEN_PACKAGES_DISPATCH_TOKEN`).
3. Import workflow downloads assets, signs packages, rebuilds indexes, and deploys Pages.

## Build tooling from source

Repository maintenance binaries (`update`, `prune`, `sign`) live in this repo.
Cargo package name remains `crateria-packages` for API stability.

```bash
git clone https://github.com/idlescreen/packages.git
cd packages
cargo build --release
```

CI runs on `master`: `fmt`, `clippy -D warnings`, `test`, and `cargo deny` advisories.

## Security

Private vulnerability reporting:
https://github.com/idlescreen/packages/security/advisories/new

Signing env (maintainers): `CRATERIA_GPG_NAME` (required), optional `CRATERIA_GPG_PATH`,
`CRATERIA_GPG_BIN`. Metadata update refuses to succeed without a usable signing key.

## License

Apache-2.0. See [LICENSE](LICENSE).
