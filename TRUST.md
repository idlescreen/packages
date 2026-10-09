# Trust model — IdleScreen one-line installer

## What the installer does

`install.sh` bootstraps a small shell-based installer that:

1. Detects the distro family (DNF / APT / Arch).
2. Adds the IdleScreen package signing key + repo drop-in.
3. Installs `idlescreen` (the metapackage: `idle-daemon`, `idle-cli`,
   `idle-savers`, `idle-tui`) and, on COSMIC, `idle-cosmic`.
4. Enables + starts the `idle-daemon.service` user unit.
5. Writes an install-time plugin-capability audit log to
   `/var/log/idlescreen/install-audit.jsonl`.

## What the installer does NOT do

- It does **not** run package installations outside your native system
  package manager (`dnf`, `apt-get`, or `pacman`).
- It does **not** contact any host other than the IdleScreen repo
  (`https://idlescreen.github.io/packages/`) and your distro's package
  mirrors.
- It does **not** capture audio or video. No telemetry.
- It does **not** open firewall ports or modify network config beyond
  adding the repo + signing key.

## Installer architecture and chain of trust

The installation pipeline operates across two repositories with strict cryptographic validation at each stage:

1. **Canonical Entry Forwarder (`idlescreen.github.io/install.sh`)**:
   - The user executes `curl -fsSL https://idlescreen.github.io/install.sh | sh`.
   - The entry forwarder downloads the channel installer from `https://idlescreen.github.io/packages/install.sh`.
   - The entry forwarder verifies the SHA-256 hash of `packages/install.sh` against its hardcoded, pinned `EXPECTED_INSTALLER_HASH` before executing it.
   - It also natively supports `--verify-self <hex>` and `--verify`.

2. **Package Channel Installer (`packages/install.sh`)**:
   - Manages identity detection, package manager configuration, and installation.
   - When executed via pipe or standalone without local sibling files, it bootstraps the helper modules (`ui.sh`, `detect.sh`, `repo.sh`, `install_core.sh`, `install_audit.sh`, `post_install.sh`, `uninstall.sh`).
   - Every module's SHA-256 is verified against hardcoded pinned checksums before the module is sourced. Tampered or mismatched modules immediately halt execution (fail-closed).
   - When `IDLE_REQUIRE_MANIFEST_SIGNATURE=1` is set, sibling `.sig` GPG signatures are verified for each module.

3. **Package Repository & Key Verification**:
   - RPM: Signing key fingerprint (`549E73C9BC9229C786E538E2FBD8FC52C7817DD2`) is verified via GPG before importing into `/etc/pki/rpm-gpg/`.
   - APT: Keyring is placed in `/etc/apt/keyrings/idlescreen-keyring.gpg` with repo definition restricted to `signed-by`.
   - Pacman: Signed sync database `idlescreen.db.tar.gz` and `.sig` are verified against the local trust anchor before configuring pacman.

4. **Checksum Synchronization (`scripts/sync_installer_checksums.sh`)**:
   - Automates checksum synchronization across modules in `packages/` and the entry forwarder in `idlescreen.github.io/`.
   - CI enforces `--check` on every commit and pull request to prevent checksum drift.

## Threat model

**In scope**:
- A compromised Pages deployment serving a tampered `install.sh`.
- A tampered RPM / DEB signed by an attacker who obtained our signing
  key.
- A man-in-the-middle on the TLS path to GitHub Pages.

**Out of scope** (operator's responsibility):
- The user's own `~/.config/idle/` (read by plugins with manifest-declared
  filesystem access).
- Third-party plugin repositories installed by the operator.

## Verification before you run

`install.sh` ships with `--verify` mode that prints SHA-256 hashes of
every shell file it would source. Recommended procedure:

```sh
# Download the script.
curl -fsSL https://idlescreen.github.io/install.sh -o install.sh

# Print the hashes.
./install.sh --verify

# Compare the printed hashes against an out-of-band source:
#   - The signed checksum manifest (below)
#   - GitHub release notes for the matching tag
#   - The signed commit on https://github.com/idlescreen/packages
#
# If hashes match, run:
./install.sh
```

## Signed checksum manifest

Every Pages deploy publishes `checksums.sha256` covering the installer,
its modules, and the key files — plus a detached signature
`checksums.sha256.asc` made with the package signing key. To verify the
installer cryptographically (stronger than a hash compare):

```sh
base=https://idlescreen.github.io/packages
curl -fsSL $base/install.sh          -o install.sh
curl -fsSL $base/checksums.sha256    -o checksums.sha256
curl -fsSL $base/checksums.sha256.asc -o checksums.sha256.asc

# If you already trust our key (post-first-install, or from a key server):
gpg --no-default-keyring \
    --keyring /etc/pki/rpm-gpg/idlescreen-key.gpg \
    --verify checksums.sha256.asc checksums.sha256

# Then check the script itself:
grep ' install.sh$' checksums.sha256 | sha256sum -c -
./install.sh
```

First-install remains trust-on-first-use over TLS — the manifest's value
is for re-verification, mirrors, and anyone cross-checking against a
copy of the key they already hold.

## Package signing keys

- RPM (DNF / Fedora / RHEL): signed by the GPG key at
  `https://idlescreen.github.io/packages/rpm/idlescreen-key.gpg`. The
  installer downloads it to `/etc/pki/rpm-gpg/idlescreen-key.gpg` and
  imports it with `rpm --import` (see `repo.sh`).
- DEB (APT / Debian / Ubuntu): signed by the same key, downloaded to
  `/etc/apt/keyrings/idlescreen-keyring.gpg`. APT refuses unsigned
  packages from the IdleScreen repo by default.
- Arch (Pacman): `install.sh` detects Arch from `/etc/os-release`, fetches
  the signing key and verifies its fingerprint against the pinned trust anchor,
  verifies the signed sync database `idlescreen.db.tar.gz` and its detached
  signature (`.sig`), and registers the repository with pacman. If a pre-built
  sync database is not published for a given release, source builds remain
  supported via `arch/idlescreen/PKGBUILD`.

The private signing key is held only in GitHub Actions secrets
(`GPG_PRIVATE_KEY`, `GPG_PASSPHRASE`). It is **never** committed to the
repo. See `docs/SIGNING.md` (in this repo) for the full SOP.

## When verification FAILS

If `--verify` shows hashes that don't match an out-of-band source:

1. Do **not** run the installer.
2. Open an issue at https://github.com/idlescreen/packages/issues.
3. Cross-check the Pages deployment commit against the `master` branch
   directly on GitHub: `https://github.com/idlescreen/packages/blob/master/install.sh`.

## Residual risks

- A compromise of GitHub Pages or the GitHub org account would allow an
  attacker to serve a tampered installer + tampered signing key + tampered
  RPM/DEB. The only mitigations are (a) out-of-band hash comparison via
  `--verify`, and (b) the project's signed commits / signed releases on
  GitHub (which GitHub's own infrastructure protects).
- A compromised user account on the install host can do anything the
  user can. The installer runs as the invoking user and as root during
  the package install step (sudo).
- The install-audit log is append-only at the file level; an attacker
  with write access to `/var/log/idlescreen/` can replace the file.

## See also

- `install_audit.sh` — the audit log format spec (in this repo)