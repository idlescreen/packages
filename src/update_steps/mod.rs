//! Per-step repository update helpers.
//!
//! Each step in the package-repository update pipeline lives in its
//! own file. This module re-exports them so the `update` binary can call them through
//! `idlescreen_packages::update_steps::*` without caring about
//! the per-file layout.

use std::process::Command;

pub mod dearmor_key;
pub mod run_createrepo;
pub mod sign_apt_release;
pub mod sign_rpm_metadata;
pub mod sign_rpms;

/// Run a [`Command`] to completion. Returns `Err` with the exit
/// status string when the child exits non-zero. Centralised so
/// the per-step files don't repeat the same `cmd.status()` +
/// success-check dance.
pub(crate) fn run_cmd(cmd: &mut Command) -> Result<(), String> {
    let status = cmd.status().map_err(|e| e.to_string())?;
    if !status.success() {
        return Err(format!("Command failed with exit status: {status}"));
    }
    Ok(())
}

pub use dearmor_key::dearmor_key;
pub use run_createrepo::run_createrepo;
pub use sign_apt_release::sign_apt_release;
pub use sign_rpm_metadata::sign_rpm_metadata;
pub use sign_rpms::sign_rpms;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn run_cmd_succeeds_on_true() {
        // `/bin/true` exits 0 in every Unix we ship to.
        let mut cmd = std::process::Command::new("true");
        assert!(run_cmd(&mut cmd).is_ok());
    }

    #[test]
    fn run_cmd_fails_on_false() {
        // `/bin/false` exits 1 — the error must propagate with the
        // "Command failed with exit status" prefix.
        let mut cmd = std::process::Command::new("false");
        let err = run_cmd(&mut cmd).expect_err("false must be an error");
        assert!(
            err.starts_with("Command failed with exit status"),
            "got {err}"
        );
    }
}
