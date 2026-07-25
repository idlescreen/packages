# Migrating to IdleScreen (`idle-*`)

Short guide for users and packagers moving from historical **Crateria / Trance / idlescreen meta** names.

## Packages (what to install)

| Role | Install now | Historical names (Provides may still resolve) |
|------|-------------|-----------------------------------------------|
| Daemon | `idle-daemon` | `trance`, `idlescreen` (virtual) |
| CLI | `idle-cli` | `idlescreen-cli` |
| Savers | `idle-savers` | `idlescreen-savers`, `trance-plugin-*` |
| TUI | `idle-tui` | `app-tui`, `idlescreen-tui`, `trance-tui` |
| COSMIC applet | `idle-cosmic` | `app-cosmic`, `idlescreen-cosmic`, `idlescreen-applet` |

One-liner (Fedora/Debian family):

```bash
curl -fsSL https://idlescreen.github.io/packages/install.sh | sh
```

## Commands

| Prefer | Aliases that still work |
|--------|-------------------------|
| `idlescreen …` or `idle …` | `trance …` |
| `idlescreen tui` | `idle-tui`, `app-tui` |
| `systemctl --user … idle-daemon.service` | `idlescreen-daemon.service` alias |

Do **not** confuse IdleScreen with System76’s **`cosmic-idle`** package (COSMIC DE idle helper). IdleScreen no longer ships a `/usr/bin/cosmic-idle` wrapper.

## Config

| Prefer | Legacy (still read) |
|--------|---------------------|
| `~/.config/idle/config.yaml` | `~/.config/trance/config.yaml` |

New writes go to **`idle`**. If you only have a `trance` config, the daemon and applet will still load it; saving from the applet writes to `idle`.

## APT / DNF repos

| Prefer | Legacy files (compat copies may remain on the host) |
|--------|-----------------------------------------------------|
| `idlescreen.list` / `idlescreen.repo` | `crateria.list` / `crateria.repo` |
| Keyring: `…/apt/idlescreen-keyring.gpg` | older `crateria-keyring` / root URL variants |

```bash
# APT (canonical)
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://idlescreen.github.io/packages/apt/idlescreen-keyring.gpg \
  | sudo tee /etc/apt/keyrings/idlescreen-keyring.gpg >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/idlescreen-keyring.gpg] https://idlescreen.github.io/packages/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/idlescreen.list >/dev/null
```

```bash
# DNF
sudo curl -fsSL https://idlescreen.github.io/packages/rpm/idlescreen.repo \
  -o /etc/yum.repos.d/idlescreen.repo
```

## D-Bus (advanced)

**Primary (prefer):**

- Service: `io.github.idlescreen.Idle`
- Path: `/io/github/idlescreen/Idle`

**Legacy (still dual-exported for upgrades):**

- Service: `io.github.ubermetroid.trance`
- Path: `/io/github/crateria/trance`

Interface methods remain `io.github.ubermetroid.trance` on both endpoints during
the migration window. Prefer packaged clients (`idle-cli` / `idle-tui` /
`idle-cosmic`) over hardcoding names.

## Environment (plugins / export)

Prefer `IDLE_*` keys; legacy `TRANCE_*` still works. Examples:

| Prefer | Legacy |
|--------|--------|
| `IDLE_EXPORT_MODE` | `TRANCE_EXPORT_MODE` |
| `IDLE_DISABLE_SANDBOX` | `TRANCE_DISABLE_SANDBOX` |
| `IDLE_RENDER_SCALE` | `TRANCE_RENDER_SCALE` |
| `IDLE_MAX_FPS` / `IDLE_TICK_HZ` | `TRANCE_MAX_FPS` / `TRANCE_TICK_HZ` |
| `RENDER_SEED` / `IDLE_RENDER_SEED` | `TRANCE_SEED` |

## Arch Linux

Experimental PKGBUILD under `packages/arch/` is **not** a full product install. Prefer Fedora/Debian packages or build from source. See `packages/arch/README.md` if present.

## Upgrade after rebrand packages land

```bash
# Fedora
sudo dnf clean all
sudo dnf upgrade 'idle-*'

# Debian/Ubuntu
sudo apt update && sudo apt upgrade
```

Then:

```bash
idlescreen doctor
```
