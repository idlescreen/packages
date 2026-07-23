//! RPM macros and GPG identity helpers for package signing.
// SPDX-License-Identifier: Apache-2.0

/// True when `name` is a usable GPG identity (non-empty after trim).
pub fn gpg_name_is_valid(name: &str) -> bool {
    !name.trim().is_empty()
}

/// Build `.rpmmacros` file content for `rpmsign`.
///
/// When `gpg_path` is `Some`, appends `%_gpg_path`. Never embeds newlines from
/// the identity fields beyond those required by the macro file format.
pub fn build_rpmmacros(gpg_name: &str, gpg_bin: &str, gpg_path: Option<&str>) -> String {
    let mut content = format!(
        "%_signature gpg\n\
         %_gpg_name {gpg_name}\n\
         %_gpgbin {gpg_bin}\n"
    );
    if let Some(path) = gpg_path {
        content.push_str(&format!("%_gpg_path {path}\n"));
    }
    content
}

/// Resolve the signing key identity: env value if non-empty, else default.
pub fn resolve_signing_key(env_val: Option<&str>, default_key: &str) -> String {
    match env_val {
        Some(v) if gpg_name_is_valid(v) => v.to_string(),
        _ => default_key.to_string(),
    }
}

/// Default GPG binary name when `CRATERIA_GPG_BIN` is unset.
pub fn resolve_gpg_bin(env_val: Option<&str>) -> String {
    match env_val {
        Some(v) if !v.is_empty() => v.to_string(),
        _ => "gpg".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn gpg_name_validation() {
        assert!(!gpg_name_is_valid(""));
        assert!(!gpg_name_is_valid("   "));
        assert!(gpg_name_is_valid("packages@example.com"));
        assert!(gpg_name_is_valid("  a  "));
    }

    #[test]
    fn macros_without_path() {
        let m = build_rpmmacros("me@ex.com", "gpg", None);
        assert!(m.contains("%_signature gpg\n"));
        assert!(m.contains("%_gpg_name me@ex.com\n"));
        assert!(m.contains("%_gpgbin gpg\n"));
        assert!(!m.contains("%_gpg_path"));
    }

    #[test]
    fn macros_with_path() {
        let m = build_rpmmacros("k", "/usr/bin/gpg", Some("/home/u/.gnupg"));
        assert!(m.contains("%_gpg_path /home/u/.gnupg\n"));
        assert!(m.contains("%_gpgbin /usr/bin/gpg\n"));
    }

    #[test]
    fn resolve_key_default() {
        assert_eq!(
            resolve_signing_key(None, "default@x"),
            "default@x"
        );
        assert_eq!(
            resolve_signing_key(Some("  "), "default@x"),
            "default@x"
        );
        assert_eq!(
            resolve_signing_key(Some("real@x"), "default@x"),
            "real@x"
        );
    }

    #[test]
    fn resolve_bin_default() {
        assert_eq!(resolve_gpg_bin(None), "gpg");
        assert_eq!(resolve_gpg_bin(Some("")), "gpg");
        assert_eq!(resolve_gpg_bin(Some("gpg2")), "gpg2");
    }
}
