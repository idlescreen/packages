# IdleScreen packages

Signed APT/RPM package host and installer for IdleScreen.

**IdleScreen** is a modular Wayland idle host and screensaver plugin suite: `idle-daemon` presents plugin effects on a layer-shell surface when the compositor reports idle; `idle-cli` / `idle-tui` / optional `idle-cosmic` control it.

Website: [https://idlescreen.github.io](https://idlescreen.github.io)

---

## Quick install

**install.sh supports:** Fedora / RHEL-family (**DNF**) and Debian / Ubuntu-family (**APT**).  
**Arch:** experimental PKGBUILD under [`arch/`](arch/) — not covered by the one-line installer.

```bash
curl -fsSL https://idlescreen.github.io/packages/install.sh | sh
```

Or, after the repo is configured:

```bash
sudo dnf install idlescreen    # Fedora / RHEL family
sudo apt install idlescreen    # Debian / Ubuntu family
# COSMIC: also  sudo dnf install idle-cosmic   /   sudo apt install idle-cosmic
```

The installer seats the product metapackage **`idlescreen`** (depends on `idle-daemon`, `idle-cli`, `idle-savers`, `idle-tui`) and on COSMIC also **`idle-cosmic`**.

**Remove** (idlescreen **2.6+** wipes the whole product stack the installer seated):

```bash
sudo dnf remove idlescreen
# or: sudo apt remove idlescreen
# Removes: idle-daemon idle-cli idle-savers idle-tui idle-saver-* idle-cosmic
#          + the idlescreen.repo / APT list drop-in
# Leaves:  ~/.config/idle (user config)
# Need 2.6+ first if an older metapackage is installed:
#   sudo dnf upgrade idlescreen && sudo dnf remove idlescreen
```

---

## What gets packaged

| Package | Role |
|---------|------|
| **`idlescreen`** | **Product metapackage** (depends on the modular stack below) |
| `idle-daemon` | Idle policy, plugin host, Wayland presentation |
| `idle-cli` | CLI (`idlescreen`) over D-Bus — does **not** install `/usr/bin/idle` (Fedora `python3-idle`) |
| `idle-savers` | Meta package pulling the official saver plugins |
| `idle-saver-*` | Individual plugins (beams, cosmos, …) |
| `idle-tui` | Terminal dashboard (`idle-tui`; also `idlescreen tui`) |
| `idle-cosmic` | Optional COSMIC panel applet |
| `idle-studio` | Optional offline render queue (not installed by `install.sh`) |

---

## Official screensavers

Ten procedural **cell-grid plugins**. The host rasterizes frames (optional wgpu cell path, CPU fallback). Preview with `idlescreen preview <name>`.

| Module | Description | Preview |
|--------|-------------|---------|
| **Beams** | Crossing vector beams | `idlescreen preview beams` |
| **Cosmos** | Starfield / nebula-style motion | `idlescreen preview cosmos` |
| **Bursts** | Expanding burst patterns | `idlescreen preview bursts` |
| **Storm** | Dense particles with flash accents | `idlescreen preview storm` |
| **Chaos** | Strange-attractor style curves | `idlescreen preview chaos` |
| **Hearth** | Warm ember / fire-like ambient | `idlescreen preview hearth` |
| **Ripple** | Expanding wave patterns | `idlescreen preview ripple` |
| **Radar** | Sweeping radar arc with blips | `idlescreen preview radar` |
| **Glyphs** | Falling character cascade | `idlescreen preview glyphs` |
| **Gnats** | Swarming agent motion | `idlescreen preview gnats` |

---

## Features (as shipped)

- **Wayland presentation** — needs compositor support for idle-notify and layer-shell (or equivalent). Strongest on COSMIC, Hyprland, and Sway; GNOME and KDE vary by protocol coverage.
- **Cell-grid plugins + host raster** — savers draw a cell grid; host turns cells into pixels (optional wgpu, CPU fallback).
- **COSMIC panel applet** — optional `idle-cosmic` package.
- **CLI and TUI** — `idlescreen`; `idlescreen tui` launches `idle-tui`.
- **Inhibit and battery** — skips presentation for logind / MPRIS2 active media; on battery, frame and simulation targets are capped (30 FPS/Hz).

---

## Manual package installation

Prefer the one-line installer above when possible.

<details>
<summary><b>Fedora / RHEL (DNF)</b></summary>

```bash
sudo curl -fsSL https://idlescreen.github.io/packages/rpm/idlescreen.repo \
  -o /etc/yum.repos.d/idlescreen.repo
sudo dnf check-update
sudo dnf install idlescreen
# COSMIC Desktop:
# sudo dnf install idle-cosmic
# Remove: sudo dnf remove idlescreen
```
</details>

<details>
<summary><b>Debian / Ubuntu (APT)</b></summary>

```bash
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://idlescreen.github.io/packages/apt/idlescreen-keyring.gpg \
  | sudo tee /etc/apt/keyrings/idlescreen-keyring.gpg >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/idlescreen-keyring.gpg] https://idlescreen.github.io/packages/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/idlescreen.list >/dev/null
sudo apt update
sudo apt install idlescreen
# COSMIC Desktop:
# sudo apt install idle-cosmic
# Remove: sudo apt remove idlescreen
```
</details>

<details>
<summary><b>Arch Linux (experimental makepkg)</b></summary>

```bash
git clone https://github.com/idlescreen/packages.git
cd packages/arch
makepkg -si
```
</details>

---

## CLI commands

```bash
idlescreen tui              # Launch idle-tui dashboard
idlescreen status           # Daemon and saver state
idlescreen on               # Enable idle screensaver (alias: enable)
idlescreen off              # Disable idle screensaver (alias: disable)
idlescreen preview <name>   # Preview a saver now
idlescreen stop             # Stop preview / presentation
idlescreen doctor           # Diagnostics
```

---

## Terminal UI (`idlescreen tui`)

```bash
idlescreen tui
# or: idle-tui
```

| Key | Action |
|-----|--------|
| `Tab` | Switch panes (Dashboard / Savers / Settings) |
| `Space` / `Enter` | Toggle or activate (context depends on pane) |
| `p` | Preview selected saver (Savers pane) |
| `c` | Install `idle-cosmic` when COSMIC is detected and the applet is missing |
| `q` / `Esc` | Quit |

---

## Maintainer docs

- [Signing SOP](docs/SIGNING.md) — required before publishing RPMs
- [Migration guide](docs/MIGRATION.md) — Crateria/Trance → IdleScreen
- [AGENT.md](AGENT.md) — hardening contract

## Links

- Website: [https://idlescreen.github.io](https://idlescreen.github.io)
- Org: [github.com/idlescreen](https://github.com/idlescreen)
- This repo hosts signed packages at [idlescreen.github.io/packages](https://idlescreen.github.io/packages/)
