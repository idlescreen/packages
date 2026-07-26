# Metapackages

## Live: `idlescreen`

Product metapackage. Requires `idle-daemon`, `idle-cli`, `idle-savers`, `idle-tui`.
Recommends `idle-cosmic`.

From **2.6.0**, erase schedules a product-stack cleanup so:

```bash
sudo dnf remove idlescreen
# or: sudo apt remove idlescreen
```

also removes modules, official `idle-saver-*` plugins, `idle-cosmic`, and the
repo drop-in written by `install.sh`. User config (`~/.config/idle`) is kept.

```bash
sudo dnf install idlescreen
sudo dnf remove idlescreen
```

Sources: `idlescreen/` (`control`, `idlescreen.spec`, remove scripts).
Build: `sh metapackages/idlescreen/build.sh` then `cargo run --release --bin sign`.
Built packages live in `rpm/pool/` and `apt/pool/main/`.
