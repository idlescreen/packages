# AGENT.md — IdleScreen packages hardening contract

Enforce on every change in this repository.

## Rust and license

- Strict Rust from first principles. Prefer `std` before crates.
- License: **Apache-2.0**.
- Vetted dependencies only.

## Constraints

- Max **250 lines** per `.rs` file.
- **Zero** `.unwrap()` or `.expect()` in production (non-test) code.
- Cargo package/lib may remain `crateria-packages` / `crateria_packages` for
  Cargo API stability until a coordinated rename.

## Testing

- Target about **3:1** test lines to production lines where practical.
- Package parse and path safety logic must have **proptest** coverage.

## Product identity

- Product brand and GitHub org: **IdleScreen**.
- Public host: **idlescreen.github.io**.
- On-disk keyring/repo filenames and GPG env vars may still use historical
  `CRATERIA_*` / `crateria-*` names until a coordinated migration.

## Git edges

- Default branch: **`master`**.
