# MIGRATION.md

This document records breaking changes that downstream packagers,
distribution channels, and end users need to act on. Each entry lists
the affected version, the change, and the migration step.

---

## Unreleased

### New — session-shell idle hand-off

**Before**: on a session shell that owns idle timing, IdleScreen ran its own idle
timer as well. Both triggered, so a screensaver could appear at one delay from
the shell's policy and another from IdleScreen's.

**After**: installers detect a shell that owns idle timing and lock, and set
`idle_enabled: false` so that shell calls IdleScreen instead. The shell keeps the
clock and the lock; IdleScreen draws. Arch installs also ship the hand-off script
at `/usr/local/bin/omarchy-launch-screensaver`.

**Migration**:
- No action needed. `idle_enabled: false` is only written when the key is
  **absent**. An explicit `true` is left alone and reported, so an existing
  deliberate choice is never overwritten.
- To hand idle timing back to IdleScreen at any point: `idlescreen enable`.
- To check the state on a running machine: `idlescreen doctor`, under
  "Session shell integration".
- Upgrading from a version that did not install the script gets it automatically
  on reinstall. It lives outside every package tree, so `idlescreen uninstall`
  removes it explicitly.

### New — `logo_file` config key

`logo_file: /absolute/path` points IdleScreen at a user-supplied ASCII-art file.
The daemon reads it and hands the contents to the renderer; the saver plugin
never opens the file. No capability or permission change is involved, and the key
is absent by default.

### Sprint 06 — saver RPM `Requires: idle` → `idle-daemon`

**Before**: `idle-saver-*.rpm` declared `Requires: idle = "*"` (no such
package exists; apt/dnf would refuse to resolve the dependency).

**After**: `Requires: idle-daemon = "*"`. The saver now correctly
depends on the daemon package that ships the runtime host.

**Migration**:
- Repos that mirrored the v2.1.0 pool: rebuild after the saver version
  bump; nothing else changes.
- End users: no action; the next `dnf upgrade` will resolve cleanly.

### Sprint 06 — install.sh signature flow (when `IDLE_REQUIRE_MANIFEST_SIGNATURE=1`)

**Before**: bootstrap modules downloaded from `idlescreen.github.io/packages`
were `source`'d without verification.

**After**: each module is verified against its sibling `*.sig` file via
`gpg --verify`. The check is gated on the same env var the runtime
honors, so behaviour for users who don't opt in is unchanged.

**Migration**:
- Release operators: sign every `*.sh` in the packages repo with the
  maintainer GPG key (`gpg --detach-sign --armor ui.sh` etc.). The CI
  signer (`cargo run --bin sign`) does not currently cover installer
  modules; manual step until Sprint 07.
- End users: no action unless they want the new check.

### Sprint 06 — audit log signing field

**Before**: `install-audit.jsonl` always emitted
`"signed_hash":null,"signer":null`.

**After**: emits a structured `signature` block capturing
`{enforce, present, sha256, signer}` so an operator can read the log
and see whether each plugin was deployed under enforcement.

**Migration**:
- Tools that grep for the old flat keys: replace `signed_hash`/`signer`
  with `signature.sha256`/`signature.signer`.

### Sprint 06 — circular DEB/RPM dep removed

**Before**: `idle-daemon` and `idle-cli` each declared the other as a
hard `Depends:` / `Requires:`; package managers refused to install
either without the other.

**After**: `idle-daemon` no longer depends on `idle-cli`. The CLI is
still recommended (and the daemon's recommended-savers list is
preserved).

**Migration**:
- Repos that ship both packages: rebuild after the change.
- End users: no action.

### Sprint 06 — CODEOWNERS drift fix

**Before**: `idlescreen/.github/CODEOWNERS` and `idle/.github/CODEOWNERS`
listed `/trance-*/` paths that don't exist.

**After**: real paths (`/idle-runner/`, `/idle-api/src/plugin_manifest/`,
`/packages/install*.sh`, etc.).

**Migration**:
- Reviewers will start receiving requests on the new paths. Expect a
  brief notification spike on the first PR after the change.

---

## 2026-08-10 — `idle` v3.1.0 channel cut

`idle-cli`, `idle-daemon`, `idle-savers` v3.1.0 ship in the apt/rpm
pool. Channel previously contained 3.0.3-1; the gap is one minor.
No breaking schema changes; capabilities and ABI are unchanged.

## 2026-06 — brand rename `trance` → `idle`

The project was renamed from `trance` to `idle` / `idlescreen` mid-2026.
Cross-references in man pages and `trance-daemon` asset filenames were
left as historical cruft; both were cleaned up in Sprint 06 —
`idle-daemon/assets/` now ships only `idle-daemon.*` files and
`cosmic/idlescreen-applet.1` documents `IDLE-APPLET`. The remaining
`trance` mentions are intentional back-compat paths (legacy
`~/.config/trance/` fallback, package `provides`/`replaces` lines).

## 2026-09-30 — configuration preservation & `/etc/xdg/idlescreen` discovery

The installer safely preserves user configuration files in `~/.config/idlescreen/config.yaml`
and `~/.config/idle/config.yaml` without clobbering existing settings. System configuration
discovery supports `/etc/xdg/idlescreen/config.yaml` as a candidate path.