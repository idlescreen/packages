//! Trust-anchor handling for the IdleScreen package channel.
//!
//! The channel's signing key is pinned by fingerprint: a downloaded key is
//! only trusted when it carries the expected fingerprint. The DNF repo file
//! is written from pinned content instead of being fetched — a fetched
//! `.repo` could swap both the trust anchor and the baseurl, which is
//! exactly what `repo.sh` refuses to do.

use std::path::{Path, PathBuf};
use std::process::Command;

/// Fingerprint of the IdleScreen package-channel signing key.
pub const CHANNEL_KEY_FPR: &str = "549E73C9BC9229C786E538E2FBD8FC52C7817DD2";

/// DNF trust-anchor directory.
pub const RPM_GPG_DIR: &str = "/etc/pki/rpm-gpg";

/// Returns true when `key_path` carries the pinned channel fingerprint.
///
/// The key file may hold more than one primary key (Ed25519 + RSA): the pin
/// holds when the expected fingerprint is among the primary-key
/// fingerprints.
pub fn key_fingerprint_matches(key_path: &Path) -> bool {
    let Ok(out) = Command::new("gpg")
        .args(["--show-keys", "--with-colons"])
        .arg(key_path)
        .output()
    else {
        return false;
    };
    if !out.status.success() {
        return false;
    }
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter(|l| l.starts_with("fpr:"))
        .filter_map(|l| l.split(':').nth(9))
        .any(|fpr| fpr.eq_ignore_ascii_case(CHANNEL_KEY_FPR))
}

/// Downloads `url` into a fresh temporary file. Returns `None` on failure.
pub fn download_to_temp(url: &str) -> Option<PathBuf> {
    let path = std::env::temp_dir().join(format!("idlescreen-key-{}.gpg", std::process::id()));
    let ok = Command::new("curl")
        .args(["-fsSL", url, "-o"])
        .arg(&path)
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if !ok {
        let _ = std::fs::remove_file(&path);
        return None;
    }
    Some(path)
}

/// Downloads the channel key, verifies its fingerprint, and installs it at
/// `dest`. The key is removed when it does not match the pin.
pub fn install_verified_key(url: &str, dest: &Path) -> bool {
    let Some(tmp) = download_to_temp(url) else {
        return false;
    };
    if !key_fingerprint_matches(&tmp) {
        let _ = std::fs::remove_file(&tmp);
        return false;
    }
    let moved = Command::new("sudo")
        .arg("install")
        .arg("-m")
        .arg("0644")
        .arg(&tmp)
        .arg(dest)
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    let _ = std::fs::remove_file(&tmp);
    moved
}

/// Writes the DNF repo file from pinned content.
pub fn write_dnf_repo(dest: &Path, repo_base: &str) -> bool {
    let body = format!(
        "[idlescreen]\n\
         name=IdleScreen RPM Repository\n\
         baseurl={repo_base}/rpm\n\
         enabled=1\n\
         gpgcheck=1\n\
         repo_gpgcheck=1\n\
         gpgkey=file://{RPM_GPG_DIR}/idlescreen-key.gpg\n\
         metadata_expire=1h\n"
    );
    let Some(tmp) = write_temp(&body) else {
        return false;
    };
    let ok = Command::new("sudo")
        .arg("install")
        .arg("-m")
        .arg("0644")
        .arg(&tmp)
        .arg(dest)
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    let _ = std::fs::remove_file(&tmp);
    ok
}

/// Writes an APT source list from pinned content.
pub fn write_apt_source(dest: &Path, repo_base: &str) -> bool {
    let body = format!(
        "deb [signed-by=/etc/apt/keyrings/idlescreen-keyring.gpg] {repo_base}/apt/ stable main\n"
    );
    let Some(tmp) = write_temp(&body) else {
        return false;
    };
    let ok = Command::new("sudo")
        .arg("install")
        .arg("-m")
        .arg("0644")
        .arg(&tmp)
        .arg(dest)
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    let _ = std::fs::remove_file(&tmp);
    ok
}

/// Writes `body` to a temporary file and returns its path.
fn write_temp(body: &str) -> Option<PathBuf> {
    let path = std::env::temp_dir().join(format!("idlescreen-repo-{}.tmp", std::process::id()));
    std::fs::write(&path, body).ok()?;
    Some(path)
}
