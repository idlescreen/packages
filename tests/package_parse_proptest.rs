//! Property tests for deb/rpm filename parsing.
// SPDX-License-Identifier: Apache-2.0

use crateria_packages::{parse_deb_filename, parse_rpm_filename};
use proptest::prelude::*;

fn pkg_name() -> impl Strategy<Value = String> {
    // Single segment: letters/digits; rpm multi-dash built separately.
    prop::string::string_regex("[a-z][a-z0-9]{0,12}").expect("name")
}

fn version_seg() -> impl Strategy<Value = String> {
    prop::string::string_regex("[0-9]+(\\.[0-9]+){0,3}").expect("ver")
}

fn arch_deb() -> impl Strategy<Value = String> {
    prop_oneof![Just("amd64".to_string()), Just("all".to_string())]
}

fn arch_rpm() -> impl Strategy<Value = String> {
    prop_oneof![
        Just("x86_64".to_string()),
        Just("noarch".to_string()),
        Just("aarch64".to_string())
    ]
}

proptest! {
    /// Well-formed deb names parse to the same name and version fields.
    #[test]
    fn prop_deb_roundtrip(
        name in pkg_name(),
        ver in version_seg(),
        arch in arch_deb(),
    ) {
        let filename = format!("{name}_{ver}_{arch}.deb");
        let id = parse_deb_filename(&filename)
            .expect("valid deb must parse");
        prop_assert_eq!(id.name, name);
        prop_assert_eq!(id.version, ver);
    }
}

proptest! {
    /// Paths and non-.deb suffixes never parse as deb packages.
    #[test]
    fn prop_deb_rejects_paths_and_bad_ext(
        name in pkg_name(),
        ver in version_seg(),
        arch in arch_deb(),
    ) {
        let base = format!("{name}_{ver}_{arch}.deb");
        let pool = format!("pool/{base}");
        let parent = format!("../{base}");
        let as_rpm = base.replace(".deb", ".rpm");
        let no_ext = base.replace(".deb", "");
        prop_assert!(parse_deb_filename(&pool).is_none());
        prop_assert!(parse_deb_filename(&parent).is_none());
        prop_assert!(parse_deb_filename(&as_rpm).is_none());
        prop_assert!(parse_deb_filename(&no_ext).is_none());
    }
}

proptest! {
    /// Well-formed single-name rpm filenames parse name + version.
    #[test]
    fn prop_rpm_roundtrip_single_name(
        name in pkg_name(),
        ver in version_seg(),
        rel in "[0-9]{1,3}",
        arch in arch_rpm(),
    ) {
        // Avoid '-' inside version so the second-to-last '-' field is version.
        prop_assume!(!ver.contains('-'));
        let filename = format!("{name}-{ver}-{rel}.{arch}.rpm");
        let id = parse_rpm_filename(&filename)
            .expect("valid rpm must parse");
        prop_assert_eq!(id.name, name);
        prop_assert_eq!(id.version, ver);
    }
}

proptest! {
    /// Multi-dash package names keep the full prefix as name.
    #[test]
    fn prop_rpm_multi_dash_name(
        segs in prop::collection::vec(pkg_name(), 2..4),
        ver in version_seg(),
        rel in "[0-9]{1,2}",
        arch in arch_rpm(),
    ) {
        prop_assume!(!ver.contains('-'));
        let name = segs.join("-");
        let filename = format!("{name}-{ver}-{rel}.{arch}.rpm");
        let id = parse_rpm_filename(&filename)
            .expect("multi-dash rpm must parse");
        prop_assert_eq!(id.name, name);
        prop_assert_eq!(id.version, ver);
    }
}

proptest! {
    /// Path components are rejected for rpm parse.
    #[test]
    fn prop_rpm_rejects_paths(
        name in pkg_name(),
        ver in version_seg(),
    ) {
        let filename = format!("{name}-{ver}-1.x86_64.rpm");
        let pool = format!("rpm/pool/{filename}");
        let win = format!("a\\{filename}");
        prop_assert!(parse_rpm_filename(&pool).is_none());
        prop_assert!(parse_rpm_filename(&win).is_none());
    }
}
