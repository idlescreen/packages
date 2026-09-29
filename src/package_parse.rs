//! Parse Debian and RPM package filenames into name + version.
// SPDX-License-Identifier: Apache-2.0

/// Package identity extracted from a filename (name + version only).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PackageId {
    pub name: String,
    pub version: String,
}

/// Parse a `.deb` filename: `name_version_arch.deb`.
///
/// Requires at least two `_`-separated fields before the extension.
/// Returns `None` if the name does not end with `.deb` or lacks fields.
pub fn parse_deb_filename(filename: &str) -> Option<PackageId> {
    if !filename.ends_with(".deb") {
        return None;
    }
    // Reject path separators — only bare filenames are accepted.
    if filename.contains('/') || filename.contains('\\') {
        return None;
    }
    let parts: Vec<&str> = filename.split('_').collect();
    if parts.len() < 2 {
        return None;
    }
    let name = parts[0];
    let version = parts[1];
    if name.is_empty() || version.is_empty() {
        return None;
    }
    Some(PackageId {
        name: name.to_string(),
        version: version.to_string(),
    })
}

/// Parse an `.rpm` filename: `name-version-release.arch.rpm`.
///
/// Uses the last two `-`-separated segments of the basename (without `.rpm`)
/// as release and version respectively; everything before is the name.
/// Multi-dash names (e.g. `trance-plugin-beams`) are supported.
pub fn parse_rpm_filename(filename: &str) -> Option<PackageId> {
    if !filename.ends_with(".rpm") {
        return None;
    }
    if filename.contains('/') || filename.contains('\\') {
        return None;
    }
    let name_without_ext = filename.strip_suffix(".rpm")?;
    let parts: Vec<&str> = name_without_ext.split('-').collect();
    // name[-name...]-version-release.arch  → need ≥3 segments
    if parts.len() < 3 {
        return None;
    }
    // version is second-to-last; last is "release.arch"
    let version = parts[parts.len() - 2];
    if version.is_empty() {
        return None;
    }
    let name = parts[0..parts.len() - 2].join("-");
    if name.is_empty() {
        return None;
    }
    Some(PackageId {
        name,
        version: version.to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deb_basic() {
        let id = parse_deb_filename("trance_0.3.57-1_amd64.deb").expect("parse");
        assert_eq!(id.name, "trance");
        assert_eq!(id.version, "0.3.57-1");
    }

    #[test]
    fn deb_rejects_non_deb() {
        assert!(parse_deb_filename("trance_0.3.57-1_amd64.rpm").is_none());
        assert!(parse_deb_filename("notadeb").is_none());
    }

    #[test]
    fn deb_rejects_path() {
        assert!(parse_deb_filename("pool/main/trance_1.0_amd64.deb").is_none());
        assert!(parse_deb_filename("..\\trance_1.0_amd64.deb").is_none());
    }

    #[test]
    fn deb_rejects_empty_fields() {
        assert!(parse_deb_filename("_1.0_amd64.deb").is_none());
        assert!(parse_deb_filename("name__amd64.deb").is_none());
        assert!(parse_deb_filename("onlyone.deb").is_none());
    }

    #[test]
    fn rpm_basic() {
        let id = parse_rpm_filename("trance-0.3.57-1.x86_64.rpm").expect("parse");
        assert_eq!(id.name, "trance");
        assert_eq!(id.version, "0.3.57");
    }

    #[test]
    fn rpm_multi_dash_name() {
        let id = parse_rpm_filename("trance-plugin-beams-0.3.8-1.x86_64.rpm").expect("parse");
        assert_eq!(id.name, "trance-plugin-beams");
        assert_eq!(id.version, "0.3.8");
    }

    #[test]
    fn rpm_rejects_short() {
        assert!(parse_rpm_filename("foo.rpm").is_none());
        assert!(parse_rpm_filename("foo-bar.rpm").is_none());
    }

    #[test]
    fn rpm_rejects_path() {
        assert!(parse_rpm_filename("rpm/pool/trance-1.0-1.x86_64.rpm").is_none());
    }
}
