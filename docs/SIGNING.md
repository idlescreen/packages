# SIGNING.md

**Owner**: @UberMetroid
**Audience**: maintainers, downstream distributors.
**Status**: living document — updated whenever the signing key rotates, the
trust model changes, or a new distribution channel is added.

---

## Trust model (TL;DR)

The Idlescreen package channel signs every package and repository
metadata with a single maintainer GPG key (`jeryd <jerydleuck@gmail.com>`).
The corresponding public key is shipped in three places:

- `apt/idlescreen-key.gpg` (ASCII-armored, APT uses it directly via
  `signed-by=…`)
- `rpm/idlescreen-key.gpg` (ASCII-armored, RPM users import it manually
  — see `repo.sh`)
- `idlescreen-keyring.gpg` (binary, legacy URL kept for back-compat;
  regenerated from the APT key on every `cargo run --bin update`)

The private key never enters the repository. It lives only in GitHub
Actions secrets (`GPG_PRIVATE_KEY`, `GPG_PASSPHRASE`) on the `packages`
repo.

## Trust-surface posture (per RULES §1.4 default-deny)

| Surface | Posture |
|---------|---------|
| APT `/etc/apt/keyrings/idlescreen-keyring.gpg` | written by `repo.sh` via `curl \| sudo tee` over TLS; no out-of-band fingerprint check yet — **residual**, see `TRUST.md` §"GitHub Pages compromise" |
| RPM `/etc/pki/rpm-gpg/idlescreen-key.gpg` | installed by `repo.sh` (`curl` → `mv` → `rpm --import`); no out-of-band fingerprint check yet — **residual**, see `TRUST.md` |
| `install.sh` bootstrap modules | when `IDLE_REQUIRE_MANIFEST_SIGNATURE` is set (any value — presence gate), every downloaded `*.sh` is verified against its sibling `*.sig` via `gpg --verify` (Sprint 06) |
| Per-plugin manifest signature | host honors `IDLE_REQUIRE_MANIFEST_SIGNATURE`; install audit log records the effective enforcement state (Sprint 06) |

## Key rotation procedure

1. Generate the new key on an offline machine:
   ```sh
   gpg --full-generate-key --armor
   ```
   Pick `RSA 4096`, set a long expiry (>= 2 years), and attach the
   `jeryd <jerydleuck@gmail.com>` identity.
2. Export armored public key to `apt/idlescreen-key.gpg` and
   `rpm/idlescreen-key.gpg`. Replace the existing files; commit on a
   dedicated `signing-rotate-<date>` branch.
3. Cross-sign the new key with the old key (held offline) so verifiers
   who pinned the old key get a continuity path.
4. Update the secret store: remove `GPG_PRIVATE_KEY` (old), add the new
   key value. Same for `GPG_PASSPHRASE`. Verify a dispatch end-to-end
   on a non-prod repo first.
5. Publish a `MIGRATION.md` entry listing the new key fingerprint and
   the cross-sig chain.
6. Notify downstream packagers on the public channel at least 30 days
   before the old key is removed from the metadata.

## Audit trail

Every install records the effective manifest-signature state in
`/var/log/idlescreen/install-audit.jsonl` (Sprint 06):

```json
{"signature":{"enforce":true,"present":true,"sha256":"…","signer":"…"}, …}
```

If `enforce` is `false` but `present` is `true`, the host never saw the
env var — the gate keys on `var_os().is_some()`, so even
`IDLE_REQUIRE_MANIFEST_SIGNATURE=0` counts as *set* (enforcing). The
presence-gate semantics are documented in `DEPLOYMENT.md` (runtime repo).

## Verification commands

```sh
# APT
apt-key finger
# RPM
rpm -qa gpg-pubkey
# Verify a single deb
dpkg-sig --verify /var/cache/apt/archives/idle-cli_*.deb
# Verify RPM metadata
rpm -K /path/to/idle-saver-beams-*.rpm
```

## Reporting issues

Open a SECURITY advisory on the affected repo, not a public issue.
The maintainer will rotate keys and publish a fresh `MIGRATION.md`
entry.