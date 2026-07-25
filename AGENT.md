# AGENT.md — IdleScreen packages hardening contract

Enforce on every change in this repository.

## Rust and license

- Strict Rust from first principles. Prefer `std` before crates.
- License: **Apache-2.0**.
- Vetted dependencies only.

## Constraints

- Max **250 lines** per `.rs` file (split modules when needed).
- **Zero** `.unwrap()` or `.expect()` in production (non-test) code.
- Cargo package/lib: **`idlescreen-packages`** / **`idlescreen_packages`**.

## Testing

- Target about **3:1** test lines to production lines where practical.
- Package parse and path safety logic must have **proptest** coverage.
- Integration tests must `use idlescreen_packages::…` (not historical crate names).

## Product identity

- Product brand and GitHub org: **IdleScreen**.
- Public host: **idlescreen.github.io**.
- Shipped packages: `idle-daemon`, `idle-cli`, `idle-savers`, `idle-tui`, `idle-cosmic` (+ optional `idle-studio`).
- GPG env: prefer **`IDLESCREEN_GPG_NAME`**, `IDLESCREEN_GPG_BIN`, `IDLESCREEN_GPG_PATH`.
  Legacy **`CRATERIA_*`** equivalents still work.
- Canonical APT keyring URL:
  `https://idlescreen.github.io/packages/apt/idlescreen-keyring.gpg`

## Signing SOP (required before publish)

1. Build RPMs/DEBs into the pool.
2. **`./sign_all.sh`** (or `cargo run --release --bin sign`) — signs **package payloads**.
3. **`./update.sh`** — rebuilds APT/RPM indexes and signs **metadata** (also re-run by `sign`).
4. Verify: `rpm -K rpm/pool/*.rpm` → every package must show **`signatures OK`**.
5. Commit pool + repodata + apt dists; push `master` (GitHub Pages).

Never publish unsigned RPMs when `gpgcheck=1` (default in `idlescreen.repo`).

## Git edges

- Default branch: **`master`**.
