// SPDX-License-Identifier: Apache-2.0
// perf: T3 · metric: bounded single-pass work; no syscalls, no locks, no allocation on the steady path · check: review

//! Honest-install messages shared across the install, update, and
//! removal flows.
//!
//! This crate only contains presentation primitives — strings
//! rendered by `install.sh`, the installer's banner, the survey
//! row emitter, and the "victory box" banner that closes a
//! successful install. No I/O, no syscalls; pure formatting.
//!
//! The split into `constants / format / survey / victory` follows
//! the install-script's own split (see `install_core.sh`,
//! `ui.sh`, `survey.sh`, `victory.sh`). Every module below is a
//! sibling to a matching `*.sh` page so the Rust ↔ shell split is
//! 1:1 and the install runbook reads top-to-bottom in either
//! direction.

pub mod constants;
pub mod format;
pub mod survey;
pub mod victory;

pub use constants::*;
pub use format::*;
pub use survey::*;
pub use victory::*;