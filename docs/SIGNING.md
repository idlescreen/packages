# Package signing SOP

IdleScreen DNF repos set `gpgcheck=1`. **RPM package payloads must be signed** before publish. Metadata signing alone is not enough.

## Environment

Prefer:

```bash
export IDLESCREEN_GPG_NAME='jerydleuck@gmail.com'   # or your key uid
# optional:
export IDLESCREEN_GPG_BIN=gpg
export IDLESCREEN_GPG_PATH="$HOME/.gnupg"
```

Legacy aliases still work: `CRATERIA_GPG_NAME`, `CRATERIA_GPG_BIN`, `CRATERIA_GPG_PATH`.

## Publish sequence

1. Build packages into `rpm/pool/` and/or `apt/pool/`.
2. **Sign RPMs:** `./sign_all.sh`  
   (`cargo run --release --bin sign` — runs `rpmsign` on every pool RPM, then `update`).
3. Or, if only indexes changed: `./update.sh` (signs APT Release + RPM `repomd.xml`; does **not** sign RPM payloads).
4. Verify:

   ```bash
   for f in rpm/pool/*.rpm; do rpm -K "$f"; done
   # every line must include: signatures OK
   ```

5. Commit pool + `rpm/repodata` + `apt/dists` + keyrings; push `master`.

## Canonical APT keyring URL

```
https://idlescreen.github.io/packages/apt/idlescreen-keyring.gpg
```

`update` regenerates `apt/idlescreen-keyring.gpg` and copies it to repo-root `idlescreen-keyring.gpg` for historical root URLs. Installers should use the **`apt/`** path.

## Never

- Publish a new RPM without step 2.
- Rely on `import-release` with empty GPG secrets.
