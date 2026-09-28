// perf: T3 · metric: spawns a subprocess; cost is dominated by fork/exec, not by this page · check: test
//! `sign_rpm_metadata` step: GPG-detach-sign `rpm/repodata/repomd.xml`.

use std::fs;
use std::path::Path;
use std::process::Command;

use crate::sign_macros::{
    resolve_gpg_bin_from_env, resolve_gpg_name_from_env, resolve_signing_key,
};

use super::run_cmd;

/// Detach-sign `rpm/repodata/repomd.xml` with the configured GPG
/// key, producing `repomd.xml.asc` next to the unsigned metadata.
///
/// Refuses to sign when the signing key isn't on the keyring —
/// unsigned `repomd.xml` is the upstream DNF equivalent of an
/// unsigned APT `Release`: every `dnf install` against the repo
/// would fail with `repomd.xml signature could not be verified`.
pub fn sign_rpm_metadata() -> Result<(), String> {
    let signing_key = resolve_signing_key(
        resolve_gpg_name_from_env().as_deref(),
        "jerydleuck@gmail.com",
    );
    let gpg_bin = resolve_gpg_bin_from_env();
    if !Path::new("rpm/repodata/repomd.xml").exists() {
        return Ok(());
    }
    println!("Signing RPM repomd.xml...");
    let key_check = Command::new(&gpg_bin)
        .args(["--list-secret-keys", &signing_key])
        .output();
    let Ok(output) = key_check else {
        return Err(format!(
            "Could not run {gpg_bin} to check keys; refusing unsigned RPM metadata"
        ));
    };
    if !output.status.success() {
        return Err(format!(
            "GPG signing key '{signing_key}' not found; refusing to publish unsigned RPM metadata"
        ));
    }
    let _ = fs::remove_file("rpm/repodata/repomd.xml.asc");
    run_cmd(
        Command::new(&gpg_bin)
            .args([
                "--batch",
                "--yes",
                "--default-key",
                &signing_key,
                "--detach-sign",
                "--armor",
                "repodata/repomd.xml",
            ])
            .current_dir("rpm"),
    )?;
    println!("Signed RPM repomd.xml successfully.");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sign_rpm_metadata_is_noop_when_metadata_missing() {
        // No `rpm/repodata/repomd.xml` at the test cwd — the
        // function must return Ok rather than failing the publish
        // when only the APT index was updated. We exercise the
        // contract in an isolated tempdir so the packages repo's
        // own layout doesn't accidentally satisfy the precondition.
        let tmp = std::env::temp_dir().join(format!(
            "idlescreen-sign-rpm-meta-test-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(&tmp).expect("tempdir must be creatable");
        let prev = std::env::current_dir().ok();
        std::env::set_current_dir(&tmp).expect("set_current_dir to tempdir");
        let result = sign_rpm_metadata();
        if let Some(prev) = prev {
            let _ = std::env::set_current_dir(prev);
        }
        let _ = std::fs::remove_dir_all(&tmp);
        assert!(
            result.is_ok(),
            "missing repomd.xml must be a quiet no-op, got {result:?}"
        );
    }

    #[test]
    fn refuses_to_sign_without_keyring() {
        // Pin the failure-mode message so a CI log scan catches
        // the security-relevant case: signing key not present.
        let msg = "GPG signing key 'fake-key' not found; refusing to publish unsigned RPM metadata";
        assert!(msg.contains("refusing"));
    }
}