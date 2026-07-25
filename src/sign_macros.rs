//! RPM macros and GPG identity helpers for package signing.
// SPDX-License-Identifier: Apache-2.0

/// True when `name` is a usable GPG identity (non-empty after trim, no
/// line breaks that would inject extra lines into `.rpmmacros`).
pub fn gpg_name_is_valid(name: &str) -> bool {
    // Reject CR/LF anywhere (before trim) so leading newlines cannot sneak past.
    !name.trim().is_empty() && !name.contains('\n') && !name.contains('\r')
}

/// True when a path/binary string is safe to embed on a single macro line.
fn macro_field_is_safe(value: &str) -> bool {
    !value.is_empty() && !value.contains('\n') && !value.contains('\r')
}

/// Build `.rpmmacros` file content for `rpmsign`.
///
/// When `gpg_path` is `Some`, appends `%_gpg_path`. Fields that contain
/// newlines are omitted/sanitized so they cannot inject extra macro lines.
/// Callers should still validate identity via [`gpg_name_is_valid`].
pub fn build_rpmmacros(gpg_name: &str, gpg_bin: &str, gpg_path: Option<&str>) -> String {
    let name = gpg_name.lines().next().unwrap_or("").trim();
    let bin = if macro_field_is_safe(gpg_bin) {
        gpg_bin
    } else {
        "gpg"
    };
    let mut content = format!(
        "%_signature gpg\n\
         %_gpg_name {name}\n\
         %_gpgbin {bin}\n"
    );
    if let Some(path) = gpg_path
        && macro_field_is_safe(path)
    {
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

/// Prefer `IDLESCREEN_GPG_NAME`, fall back to legacy `CRATERIA_GPG_NAME`.
pub fn resolve_gpg_name_from_env() -> Option<String> {
    for key in ["IDLESCREEN_GPG_NAME", "CRATERIA_GPG_NAME"] {
        if let Ok(v) = std::env::var(key)
            && gpg_name_is_valid(&v)
        {
            return Some(v);
        }
    }
    None
}

/// Default GPG binary name when `IDLESCREEN_GPG_BIN` / `CRATERIA_GPG_BIN` unset.
pub fn resolve_gpg_bin(env_val: Option<&str>) -> String {
    match env_val {
        Some(v) if macro_field_is_safe(v) => v.to_string(),
        _ => "gpg".to_string(),
    }
}

/// Prefer `IDLESCREEN_GPG_BIN`, fall back to `CRATERIA_GPG_BIN`, then `gpg`.
pub fn resolve_gpg_bin_from_env() -> String {
    for key in ["IDLESCREEN_GPG_BIN", "CRATERIA_GPG_BIN"] {
        if let Ok(v) = std::env::var(key)
            && macro_field_is_safe(&v)
        {
            return v;
        }
    }
    "gpg".into()
}

/// Prefer `IDLESCREEN_GPG_PATH`, fall back to `CRATERIA_GPG_PATH`.
pub fn resolve_gpg_path_from_env() -> Option<String> {
    for key in ["IDLESCREEN_GPG_PATH", "CRATERIA_GPG_PATH"] {
        if let Ok(v) = std::env::var(key)
            && !v.is_empty()
            && !v.contains('\n')
            && !v.contains('\r')
        {
            return Some(v);
        }
    }
    None
}

/// True when skip-install of rpm-sign is requested (either env name).
pub fn skip_rpm_sign_install_from_env() -> bool {
    std::env::var_os("IDLESCREEN_SKIP_RPM_SIGN_INSTALL").is_some()
        || std::env::var_os("CRATERIA_SKIP_RPM_SIGN_INSTALL").is_some()
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
        assert!(!gpg_name_is_valid("evil\n%_gpg_name other"));
        assert!(!gpg_name_is_valid("a\rb"));
        assert!(!gpg_name_is_valid("\na"));
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
    fn macros_strip_newline_injection() {
        let m = build_rpmmacros("good@x\n%_gpg_name evil", "gpg\n%_foo bar", Some("p\nq"));
        assert!(m.contains("%_gpg_name good@x\n"));
        assert!(!m.contains("evil"));
        assert!(m.contains("%_gpgbin gpg\n"));
        assert!(!m.contains("%_foo"));
        assert!(!m.contains("%_gpg_path"));
    }

    #[test]
    fn resolve_key_default() {
        assert_eq!(resolve_signing_key(None, "default@x"), "default@x");
        assert_eq!(resolve_signing_key(Some("  "), "default@x"), "default@x");
        assert_eq!(resolve_signing_key(Some("real@x"), "default@x"), "real@x");
        assert_eq!(resolve_signing_key(Some("a\nb"), "default@x"), "default@x");
    }

    #[test]
    fn resolve_bin_default() {
        assert_eq!(resolve_gpg_bin(None), "gpg");
        assert_eq!(resolve_gpg_bin(Some("")), "gpg");
        assert_eq!(resolve_gpg_bin(Some("gpg2")), "gpg2");
        assert_eq!(resolve_gpg_bin(Some("gpg\nevil")), "gpg");
    }
}
