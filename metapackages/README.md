# Metapackages (historical / archive)

The **live** product is shipped as modular packages in `rpm/pool` and `apt/pool`:

- `idle-daemon`, `idle-cli`, `idle-savers`, `idle-tui`, `idle-cosmic`
- optional: `idle-studio` (RPM; may lag on APT)

Directories under this folder (`app-cosmic`, `idlescreen`, `idlescreen-cosmic`, …) are **legacy packaging sketches**. They are **not** the source of truth for the published pool.

- Prefer: `curl -fsSL https://idlescreen.github.io/packages/install.sh | sh`
- Or install the modular packages listed above.
- `idle-cosmic` **Provides** transitional names such as `app-cosmic` / `idlescreen-applet` for upgrades.

Do not build these metas for new releases unless they are rewritten to match the live package graph.
