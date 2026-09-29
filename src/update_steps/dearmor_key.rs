//! `dearmor_key` step: regenerate the binary GPG keyring from the
//! ASCII-armored source.

use std::fs;
use std::process::Command;

/// Convert `apt/idlescreen-key.gpg` (ASCII-armored) into
/// `apt/idlescreen-keyring.gpg` (binary) using `gpg --dearmor`. Also
/// drops a root copy of the keyring for any installer that still
/// uses the historical root URL.
///
/// Refuses to succeed if `gpg --dearmor` exits non-zero — leaving
/// a half-written keyring would cause APT clients to reject the
/// repository signature.
pub fn dearmor_key() -> Result<(), String> {
    println!("Regenerating binary GPG keyring...");
    let gpg_file = fs::File::create("apt/idlescreen-keyring.gpg").map_err(|e| e.to_string())?;
    let key_file = fs::File::open("apt/idlescreen-key.gpg").map_err(|e| e.to_string())?;

    let status = Command::new("gpg")
        .arg("--dearmor")
        .stdin(key_file)
        .stdout(gpg_file)
        .status()
        .map_err(|e| e.to_string())?;

    if !status.success() {
        return Err(format!("gpg --dearmor failed with status: {status}"));
    }
    // Root copy for any installers still using the historical root URL.
    let _ = fs::copy("apt/idlescreen-keyring.gpg", "idlescreen-keyring.gpg");
    Ok(())
}

#[cfg(test)]
mod tests {
    // dearmor_key depends on filesystem layout (apt/idlescreen-key.gpg,
    // gpg binary). The unit tests for the publish path live in
    // `update_steps::tests` (integration) so this page's tests
    // cover only the contract that can be exercised without the
    // filesystem: the helper fails closed when the source is
    // missing.

    #[test]
    fn dearmor_key_fails_closed_when_source_missing() {
        // Source key file doesn't exist; the function must fail
        // closed instead of producing an empty keyring. We
        // exercise the contract in an isolated tempdir so the
        // packages repo's own layout doesn't accidentally satisfy
        // the precondition.
        let tmp = std::env::temp_dir().join(format!(
            "idlescreen-dearmor-key-test-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(&tmp).expect("tempdir must be creatable");
        let prev = std::env::current_dir().ok();
        std::env::set_current_dir(&tmp).expect("set_current_dir to tempdir");
        let result = super::dearmor_key();
        if let Some(prev) = prev {
            let _ = std::env::set_current_dir(prev);
        }
        let _ = std::fs::remove_dir_all(&tmp);
        assert!(
            result.is_err(),
            "missing source must be an error, got {result:?}"
        );
    }
}
