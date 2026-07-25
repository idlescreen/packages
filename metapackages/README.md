# Metapackages

## Live product meta

**`idlescreen/`** — product metapackage (empty package that **Requires** the modular stack).

| Action | Command |
|--------|---------|
| Install | `sudo dnf install idlescreen` / `sudo apt install idlescreen` |
| Remove | `sudo dnf remove idlescreen` / `sudo apt remove idlescreen` |

Pulls: `idle-daemon`, `idle-cli`, `idle-savers`, `idle-tui`. Recommends `idle-cosmic`.

Build (RPM example):

```bash
# from packages/ with rpmbuild or podman — see idlescreen/idlescreen.spec
# ship to rpm/pool/ + apt/pool/main/, then ./sign_all.sh
```

`install.sh` always installs modular packages **and** `idlescreen` so brand install/remove works.

## Legacy sketches

`app-cosmic/`, `idlescreen-cosmic/`, … are historical and not the published product graph.
