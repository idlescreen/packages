# IdleScreen install (current)

## Install

```bash
curl -fsSL https://idlescreen.github.io/packages/install.sh | sh
# or:
sudo dnf install idlescreen
# COSMIC applet (if not pulled):
# sudo dnf install idle-cosmic
```

| Package | Role |
|---------|------|
| **idlescreen** | Product metapackage (depends on modular stack) |
| idle-daemon | Wayland idle host |
| idle-cli | CLI (`idlescreen` / `idle`) |
| idle-savers | Official saver plugins |
| idle-tui | Terminal dashboard |
| idle-cosmic | COSMIC panel applet |

## Remove

```bash
sudo dnf remove idlescreen
# full wipe of modules if needed:
# sudo dnf remove idle-daemon idle-cli idle-savers idle-tui idle-cosmic
```

## Config

`~/.config/idle/config.yaml` only (daemon may copy once from legacy `~/.config/trance/` if present).

## D-Bus (2.5+)

| | |
|--|--|
| Service / interface | `io.github.idlescreen.Idle` |
| Object path | `/io/github/idlescreen/Idle` |

Legacy bus names are **not** dual-exported.

## Commands

```bash
idlescreen tui
idlescreen status
idlescreen preview beams
idlescreen doctor
```

Alias: `idle` is the same CLI binary.

## Note

System76’s **`cosmic-idle`** package is unrelated; do not remove it when uninstalling IdleScreen.
