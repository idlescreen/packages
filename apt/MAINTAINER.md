# Maintainer Guide (How to Update Packages)

This guide documents how to add new package versions and update the repository metadata indices.

## Steps to Update

1.  **Copy the newly compiled packages** into the repository.
    *   Example: `cp ../trance/target/debian/*.deb pool/main/`

2.  **Run the update indexer script** from the repository root to regenerate the database indices and cryptographically sign the Release files:
    ```bash
    ./update.sh
    ```

3.  **Commit and push the changes** to GitHub to make them available to clients:
    ```bash
    git add .
    git commit -m "Add packages and update index"
    git push origin main
    ```

## Pool Pruning

The pool directory grows unboundedly with every release. To prune the
pool to the latest 3 versions of each package:

```bash
./scripts/prune.sh          # default: keep latest 3
./scripts/prune.sh 5        # keep latest 5
```

Run this before regenerating the index in step 2 above.

## GPG Key Rotation Policy

The repository signing key is committed at `apt/crateria-key.gpg`
as the **public key only** (the private key is held offline by the
maintainer). Rotation policy:

*   Rotate annually, or immediately on suspected compromise.
*   After rotation, re-sign the `Release` file with the new key.
*   Old releases remain valid as long as clients have the old key in
    their keyring; clients should be notified to update.
*   Publish the new public key fingerprint in this file and in
    `apt/README.md`.

## Signing policy (fail-closed)

`./update.sh` / `cargo run --bin update` **must** sign both:

* APT `Release` / `InRelease` / `Release.gpg`
* RPM `repodata/repomd.xml.asc`

If the secret key is missing, the update tool **exits with an error**. Do not force-publish unsigned indexes. Individual RPMs still need `./sign_all.sh` so `gpgcheck=1` clients accept packages.

## Version / tag hygiene

| Artifact | Expected alignment |
| :--- | :--- |
| `trance-daemon` crate version | Git tag `vX.Y.Z` on `trance` |
| Published `trance_X.Y.Z-1_amd64.deb` | Same `X.Y.Z` |
| `trance-plugins` crates | Tag `vA.B.C` when plugin ABI/content ships |
| `trance-plugins-all` meta | Tracks core `trance` version |

Create the git tag when you release packages — do not leave tags lagging behind published debs (historical gap: tags stopped at `v0.3.16` while packages reached `0.3.25`).

## Guidelines
*   **Aesthetics**: The Gentoo/systemd-style TUI progress formatting is great. Preserve this clean, text-based interactive styling for installer and setup scripts.
