//! Pool path construction and path-safety helpers for package tooling.
// SPDX-License-Identifier: Apache-2.0

use std::ffi::OsStr;
use std::path::{Component, Path, PathBuf};

/// Destination for a swept `.deb` under the apt pool.
///
/// Returns `None` when `filename` is not a single safe path segment.
pub fn deb_pool_dest(filename: &OsStr) -> Option<PathBuf> {
    safe_join_under(Path::new("apt/pool/main"), filename)
}

/// Destination for a swept `.rpm` under the rpm pool.
///
/// Returns `None` when `filename` is not a single safe path segment.
pub fn rpm_pool_dest(filename: &OsStr) -> Option<PathBuf> {
    safe_join_under(Path::new("rpm/pool"), filename)
}

/// Map a package file extension to its pool destination path.
///
/// Returns `None` for unknown extensions or unsafe filenames.
pub fn package_sweep_dest(filename: &OsStr, ext: &str) -> Option<PathBuf> {
    match ext {
        "deb" => deb_pool_dest(filename),
        "rpm" => rpm_pool_dest(filename),
        _ => None,
    }
}

/// True when `path` is a regular-looking `.rpm` file path (by extension).
pub fn is_rpm_path(path: &Path) -> bool {
    path.extension().and_then(|s| s.to_str()) == Some("rpm")
}

/// Join `filename` under `base` only if `filename` is a single safe segment.
///
/// Rejects empty names, `.`, `..`, absolute paths, and any name containing a
/// path separator. On success the result is always a child of `base`.
pub fn safe_join_under(base: &Path, filename: &OsStr) -> Option<PathBuf> {
    let name = filename.to_str()?;
    if name.is_empty() || name == "." || name == ".." {
        return None;
    }
    if name.contains('/') || name.contains('\\') {
        return None;
    }
    // OsStr as path must be a single Normal component.
    let as_path = Path::new(name);
    if as_path.is_absolute() {
        return None;
    }
    let mut comps = as_path.components();
    match (comps.next(), comps.next()) {
        (Some(Component::Normal(_)), None) => Some(base.join(name)),
        _ => None,
    }
}

/// True if `candidate` is lexically under `base` (prefix of components).
pub fn is_under_base(base: &Path, candidate: &Path) -> bool {
    let base_comps: Vec<_> = base.components().collect();
    let cand_comps: Vec<_> = candidate.components().collect();
    cand_comps.starts_with(&base_comps) && cand_comps.len() > base_comps.len()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::OsString;

    #[test]
    fn sweep_dest_deb_rpm() {
        let f = OsStr::new("pkg_1.0_amd64.deb");
        assert_eq!(
            package_sweep_dest(f, "deb").expect("deb"),
            PathBuf::from("apt/pool/main/pkg_1.0_amd64.deb")
        );
        let r = OsStr::new("pkg-1.0-1.x86_64.rpm");
        assert_eq!(
            package_sweep_dest(r, "rpm").expect("rpm"),
            PathBuf::from("rpm/pool/pkg-1.0-1.x86_64.rpm")
        );
        assert!(package_sweep_dest(f, "txt").is_none());
    }

    #[test]
    fn sweep_dest_rejects_unsafe_names() {
        assert!(package_sweep_dest(OsStr::new(".."), "deb").is_none());
        assert!(package_sweep_dest(OsStr::new("a/b.deb"), "deb").is_none());
        assert!(package_sweep_dest(OsStr::new("a\\b.rpm"), "rpm").is_none());
        assert!(deb_pool_dest(OsStr::new("")).is_none());
        assert!(rpm_pool_dest(OsStr::new(".")).is_none());
    }

    #[test]
    fn is_rpm_extension() {
        assert!(is_rpm_path(Path::new("foo.rpm")));
        assert!(!is_rpm_path(Path::new("foo.deb")));
        assert!(!is_rpm_path(Path::new("foo")));
    }

    #[test]
    fn safe_join_accepts_plain_name() {
        let base = Path::new("rpm/pool");
        let out = safe_join_under(base, OsStr::new("pkg-1.0-1.x86_64.rpm")).expect("ok");
        assert_eq!(out, PathBuf::from("rpm/pool/pkg-1.0-1.x86_64.rpm"));
        assert!(is_under_base(base, &out));
    }

    #[test]
    fn safe_join_rejects_traversal() {
        let base = Path::new("/var/lib/pool");
        assert!(safe_join_under(base, OsStr::new("..")).is_none());
        assert!(safe_join_under(base, OsStr::new(".")).is_none());
        assert!(safe_join_under(base, OsStr::new("")).is_none());
        assert!(safe_join_under(base, OsStr::new("a/b")).is_none());
        assert!(safe_join_under(base, OsStr::new("a\\b")).is_none());
        assert!(safe_join_under(base, OsStr::new("/etc/passwd")).is_none());
    }

    #[test]
    fn safe_join_rejects_parent_in_name() {
        // ".." as the whole name already covered; multi-component via sep.
        let base = Path::new("apt/pool/main");
        assert!(safe_join_under(base, OsStr::new("..")).is_none());
        let bad = OsString::from("evil");
        let ok = safe_join_under(base, &bad).expect("plain");
        assert!(is_under_base(base, &ok));
    }

    #[test]
    fn is_under_base_requires_strict_child() {
        let base = Path::new("/var/lib/pool");
        assert!(!is_under_base(base, base));
        assert!(!is_under_base(base, Path::new("/var/lib")));
        assert!(!is_under_base(base, Path::new("/var/lib/other")));
        assert!(is_under_base(base, Path::new("/var/lib/pool/a.rpm")));
        assert!(!is_under_base(base, Path::new("/var/lib/pool-extra/x")));
    }
}
