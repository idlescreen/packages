# packages

<div align="center">

| Security Pillar | Verification Badge |
| :--- | :---: |
| **Platform Standard** | [![secured by studio2201][b-studio]][u-home] |
| **Credential Defense** | [![snip][b-snip]][u-snip] |
| **Supply Chain Surface** | [![vigil][b-vigil]][u-vigil] |
| **Post-Quantum Cryptography** | [![aegis][b-aegis]][u-aegis] |
| **Build Provenance & SLSA** | [![proven][b-proven]][u-proven] |
| **Repository Governance** | [![boneyard][b-boneyard]][u-boneyard] |

[b-studio]: https://img.shields.io/badge/secured%20by-studio2201-2f6f5e?logo=shield
[u-home]: https://studio2201.com
[b-snip]: https://img.shields.io/badge/snip-0%20secrets-2f6f5e?logo=shield
[u-snip]: https://studio2201.com/snip
[b-vigil]: https://img.shields.io/badge/vigil-0%20dependencies-2f6f5e?logo=shield
[u-vigil]: https://studio2201.com/vigil
[b-aegis]: https://img.shields.io/badge/aegis-PQC%20compliant-2f6f5e?logo=shield
[u-aegis]: https://studio2201.com/aegis
[b-proven]: https://img.shields.io/badge/proven-ML--DSA--65%20verified-2f6f5e?logo=shield
[u-proven]: https://studio2201.com/proven
[b-boneyard]: https://img.shields.io/badge/boneyard-maintained-2f6f5e?logo=shield
[u-boneyard]: https://studio2201.com/boneyard

</div>

The signed package channel — APT, RPM and pacman repos served at
`idlescreen.github.io/packages`, fed by release imports from every product
repo. Part of [IdleScreen](https://idlescreen.github.io) — modular Wayland
screensavers for Linux.

## Install

The web installer detects your package manager and configures the right
channel. It is the only path that writes the trust anchor for you.

```sh
curl -fsSL https://idlescreen.github.io/install.sh | sh
```

Verify the download before you run it:

```sh
curl -fsSL https://idlescreen.github.io/install.sh -o install.sh
./install.sh --verify     # print SHA-256 of the installer and its modules
```

Then, by channel:

| Channel | Command |
|---|---|
| **Web installer** | `curl -fsSL https://idlescreen.github.io/install.sh | sh` |
| **DNF / RPM** | `./install.sh` (writes `/etc/yum.repos.d/idlescreen.repo`) |
| **APT / DEB** | `./install.sh` (writes `/etc/apt/sources.list.d/idlescreen.list`) |
| **pacman / Arch** | `./install.sh` (writes `/etc/xdg/idlescreen/idlescreen.db`) |

Once a channel is configured, the product package is a one-liner:

```sh
dnf install idlescreen        # Fedora, Nobara, RHEL family
apt-get install idlescreen    # Debian, Ubuntu, Mint, Pop!_OS, elementary
pacman -S idlescreen          # Arch, EndeavourOS, Garuda, CachyOS
```

### Arch without the binary channel

The pacman channel is served from a signed dylib database, so `install.sh`
needs `arch/idlescreen.db.tar.gz` published for the current release. If it is
not yet there, build from source instead:

```sh
git clone https://github.com/idlescreen/packages
cd packages/arch/idlescreen
makepkg -si
```

That PKGBUILD compiles the runtime, CLI, TUI and saver crates from their
release tags and produces `idle-daemon`, `idle-cli`, `idle-tui`,
`idle-savers` and the `idlescreen` metapackage. It is a full source build —
expect tens of minutes.

## Configuration & Preservation

The IdleScreen installer preserves existing user and system configurations without clobbering:
- User configs: `~/.config/idlescreen/config.yaml` and `~/.config/idle/config.yaml`
- System defaults: `/etc/xdg/idlescreen/config.yaml`, `/etc/idlescreen/config.yaml`, and `/etc/idle/config.yaml`

Existing files are preserved completely across installs, upgrades, and channel re-syncs.

## License

Apache-2.0 · © 2026 IdleScreen
