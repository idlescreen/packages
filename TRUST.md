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

- It does **not** run anything outside `dnf` / `apt-get` / `pacman`.
- It does **not** contact any host other than the IdleScreen repo
  (`https://idlescreen.github.io/packages/`) and your distro's package
  mirrors.
- It does **not** capture audio or video. No telemetry.
- It does **not** open firewall ports or modify network config beyond
  adding the repo + signing key.

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
curl -fsSL https://idlescreen.github.io/packages/install.sh -o install.sh

# Print the hashes.
./install.sh --verify

# Compare the printed hashes against an out-of-band source:
#   - GitHub release notes for the matching tag
#   - The signed commit on https://github.com/idlescreen/packages
#   - A maintainer post on the project mailing list / Matrix / IRC
#
# If hashes match, run:
./install.sh
```

For automated deploys, hard-pin a specific release by setting
`IDLESCREEN_VERSION=4.0.5` (or whatever the latest tagged release is) in
the environment before invoking the installer.

## Package signing keys

- RPM (DNF / Fedora / RHEL): signed by the GPG key at
  `https://idlescreen.github.io/packages/idlescreen-keyring.gpg`. The
  installer downloads + installs the keyring to `/etc/pki/rpm-gpg/`.
- DEB (APT / Debian / Ubuntu): signed by the same key, downloaded to
  `/etc/apt/keyrings/idlescreen-keyring.gpg`. APT refuses unsigned
  packages from the IdleScreen repo by default.
- Arch (experimental PKGBUILD): GPG signature verified via `pacman-key`.

The private signing key is held only in GitHub Actions secrets
(`GPG_PRIVATE_KEY`, `GPG_PASSPHRASE`). It is **never** committed to the
repo. See `docs/SIGNING.md` (in the org repo) for the full SOP.

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