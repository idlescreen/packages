//! `sign_rpms` step: GPG-sign every `.rpm` in `rpm/pool/`.

use std::fs;
use std::path::Path;
use std::process::Command;

use crate::sign_macros::{resolve_gpg_name_from_env, resolve_signing_key};

use super::run_cmd;

/// Sign every `.rpm` file under `rpm/pool/` with the configured
/// GPG key. No-op when the pool is empty or missing — the first
/// publish of a new repository, or an RPM-cleanup pass, both
/// legitimately produce a zero-file pool.
///
/// Refuses to fail silently: a non-zero `rpmsign` exit propagates
/// so unsigned RPMs never reach the public pool.
pub fn sign_rpms() -> Result<(), String> {
    let signing_key = resolve_signing_key(
        resolve_gpg_name_from_env().as_deref(),
        "jerydleuck@gmail.com",
    );
    let rpm_pool = Path::new("rpm/pool");
    if !rpm_pool.exists() {
        return Ok(());
    }

    let mut rpms = Vec::new();
    if let Ok(entries) = fs::read_dir(rpm_pool) {
        for entry in entries.flatten() {
            if entry.path().extension().and_then(|s| s.to_str()) == Some("rpm") {
                rpms.push(entry.path());
            }
        }
    }

    if rpms.is_empty() {
        return Ok(());
    }

    println!("Signing {} RPMs...", rpms.len());
    let mut cmd = Command::new("rpmsign");
    cmd.arg("--addsign").arg("--key-id").arg(&signing_key);
    for rpm in &rpms {
        cmd.arg(rpm);
    }
    run_cmd(&mut cmd)?;
    println!("Signed RPMs successfully.");
    Ok(())
}

#[cfg(test)]
mod tests {
    // sign_rpms depends on `rpm/pool/` layout and the GPG signing
    // key. The integration test lives in `tests/`.

    #[test]
    fn sign_rpms_is_noop_when_pool_missing() {
        // No `rpm/pool/` directory at the test cwd — the function
        // must return Ok rather than erroring out, so the first
        // APT-only publish doesn't fail because there's no RPM
        // content yet. We exercise in an isolated tempdir so the
        // packages repo's own layout doesn't accidentally satisfy
        // the precondition.
        let tmp = std::env::temp_dir().join(format!(
            "idlescreen-sign-rpms-test-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(&tmp).expect("tempdir must be creatable");
        let prev = std::env::current_dir().ok();
        std::env::set_current_dir(&tmp).expect("set_current_dir to tempdir");
        let result = super::sign_rpms();
        if let Some(prev) = prev {
            let _ = std::env::set_current_dir(prev);
        }
        let _ = std::fs::remove_dir_all(&tmp);
        assert!(
            result.is_ok(),
            "missing rpm/pool must be a quiet no-op, got {result:?}"
        );
    }
}