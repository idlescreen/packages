# Arch Linux (experimental)

**Status: incomplete — not a full IdleScreen install.**

This directory currently holds a **PKGBUILD focused on the COSMIC applet** (`idle-cosmic`), not the complete product matrix.

## What is missing

A complete install needs at least:

- `idle-daemon`
- `idle-cli`
- `idle-savers` (or individual `idle-saver-*`)
- `idle-tui`
- `idle-cosmic` (COSMIC only)

Only the applet PKGBUILD is present here. Running `makepkg -si` does **not** give you `idlescreen tui` or the full saver set by itself.

## Recommended paths

1. **Fedora / Debian family** (supported):

   ```bash
   curl -fsSL https://idlescreen.github.io/packages/install.sh | sh
   ```

2. **Arch:** build components from source (idle monorepo + savers + idle-tui + idle-cosmic), or contribute PKGBUILDs for the full matrix.

## Experimental applet PKGBUILD

```bash
cd packages/arch
# Review PKGBUILD first — checksums / deps may lag
makepkg -si
```

See also: [docs/MIGRATION.md](../docs/MIGRATION.md).
