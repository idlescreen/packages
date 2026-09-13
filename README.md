# packages

The signed package channel — APT and RPM repos served at
`idlescreen.github.io/packages`, fed by release imports from every product
repo. Part of [IdleScreen](https://idlescreen.github.io) — modular Wayland
screensavers for Linux.

## Use

```sh
curl -fsSL https://idlescreen.github.io/packages/install.sh | sh
```

The installer (this repo) writes the repo config + GPG key, then installs
the `idlescreen` product package — the router that pulls the whole stack.
See `TRUST.md` for the trust model and signature verification.

## Develop

Shell scripts + the `install_honesty` test crate — installer claims are
verified against reality (no marketing-speak in prompts, package lists
match the teardown contract).

```sh
git clone https://github.com/idlescreen/packages.git && cd packages
cargo test          # honesty checks over the installer scripts
./update.sh         # regenerate pool indexes after adding artifacts
```

## License

Apache-2.0 · © 2026 IdleScreen
