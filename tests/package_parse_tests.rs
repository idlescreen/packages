//! Property tests for deb/rpm filename parsing — std-only, deterministic.

use idlescreen_packages::{parse_deb_filename, parse_rpm_filename};

mod common;
use common::{Rng, arch_deb, arch_rpm, pkg_name, rel_num, version_seg};

const CASES: usize = 512;

/// Well-formed deb names parse to the same name and version fields.
#[test]
fn prop_deb_roundtrip() {
    let mut rng = Rng::new(0xDE8_0001);
    for _ in 0..CASES {
        let name = pkg_name(&mut rng, 12);
        let ver = version_seg(&mut rng);
        let arch = arch_deb(&mut rng);
        let filename = format!("{name}_{ver}_{arch}.deb");
        let id = parse_deb_filename(&filename).expect("valid deb must parse");
        assert_eq!(id.name, name);
        assert_eq!(id.version, ver);
    }
}

/// Paths and non-.deb suffixes never parse as deb packages.
#[test]
fn prop_deb_rejects_paths_and_bad_ext() {
    let mut rng = Rng::new(0xDE8_0002);
    for _ in 0..CASES {
        let name = pkg_name(&mut rng, 12);
        let ver = version_seg(&mut rng);
        let arch = arch_deb(&mut rng);
        let base = format!("{name}_{ver}_{arch}.deb");
        let pool = format!("pool/{base}");
        let parent = format!("../{base}");
        let as_rpm = base.replace(".deb", ".rpm");
        let no_ext = base.replace(".deb", "");
        assert!(parse_deb_filename(&pool).is_none());
        assert!(parse_deb_filename(&parent).is_none());
        assert!(parse_deb_filename(&as_rpm).is_none());
        assert!(parse_deb_filename(&no_ext).is_none());
    }
}

/// Well-formed single-name rpm filenames parse name + version.
#[test]
fn prop_rpm_roundtrip_single_name() {
    let mut rng = Rng::new(0xDE8_0003);
    for _ in 0..CASES {
        let name = pkg_name(&mut rng, 12);
        let ver = version_seg(&mut rng);
        let rel = rel_num(&mut rng, 3);
        let arch = arch_rpm(&mut rng);
        let filename = format!("{name}-{ver}-{rel}.{arch}.rpm");
        let id = parse_rpm_filename(&filename).expect("valid rpm must parse");
        assert_eq!(id.name, name);
        assert_eq!(id.version, ver);
    }
}

/// Multi-dash package names keep the full prefix as name.
#[test]
fn prop_rpm_multi_dash_name() {
    let mut rng = Rng::new(0xDE8_0004);
    for _ in 0..CASES {
        let segs: Vec<String> = (0..rng.range(2, 3))
            .map(|_| pkg_name(&mut rng, 12))
            .collect();
        let ver = version_seg(&mut rng);
        let rel = rel_num(&mut rng, 2);
        let arch = arch_rpm(&mut rng);
        let name = segs.join("-");
        let filename = format!("{name}-{ver}-{rel}.{arch}.rpm");
        let id = parse_rpm_filename(&filename).expect("multi-dash rpm must parse");
        assert_eq!(id.name, name);
        assert_eq!(id.version, ver);
    }
}

/// Path components are rejected for rpm parse.
#[test]
fn prop_rpm_rejects_paths() {
    let mut rng = Rng::new(0xDE8_0005);
    for _ in 0..CASES {
        let name = pkg_name(&mut rng, 12);
        let ver = version_seg(&mut rng);
        let filename = format!("{name}-{ver}-1.x86_64.rpm");
        let pool = format!("rpm/pool/{filename}");
        let win = format!("a\\{filename}");
        assert!(parse_rpm_filename(&pool).is_none());
        assert!(parse_rpm_filename(&win).is_none());
    }
}
