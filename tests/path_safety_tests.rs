//! Property tests for pool path construction and path-safety — std-only.

use idlescreen_packages::{
    deb_pool_dest, is_under_base, package_sweep_dest, rpm_pool_dest, safe_join_under,
};
use std::ffi::OsStr;
use std::path::{Path, PathBuf};

mod common;
use common::{Rng, safe_segment};

const CASES: usize = 512;

/// Safe single-segment names join under base and stay under base.
#[test]
fn prop_safe_join_under_base() {
    let mut rng = Rng::new(0xBA5E_0001);
    for _ in 0..CASES {
        let n = rng.range(1, 3) as usize;
        let base_segs: Vec<String> = (0..n).map(|_| safe_segment(&mut rng)).collect();
        let file = safe_segment(&mut rng);
        let mut base = PathBuf::new();
        for s in &base_segs {
            base.push(s);
        }
        let out = safe_join_under(&base, OsStr::new(&file)).expect("safe segment must join");
        assert!(is_under_base(&base, &out));
        assert_eq!(out, base.join(&file));
    }
}

/// Names with `/` or `\\` are always rejected.
#[test]
fn prop_reject_separators() {
    let mut rng = Rng::new(0xBA5E_0002);
    for _ in 0..CASES {
        let left = safe_segment(&mut rng);
        let right = safe_segment(&mut rng);
        let base = Path::new("pool");
        let slash = format!("{left}/{right}");
        let back = format!("{left}\\{right}");
        assert!(safe_join_under(base, OsStr::new(&slash)).is_none());
        assert!(safe_join_under(base, OsStr::new(&back)).is_none());
        assert!(package_sweep_dest(OsStr::new(&slash), "deb").is_none());
        assert!(package_sweep_dest(OsStr::new(&back), "rpm").is_none());
    }
}

/// `.` and `..` and empty are rejected.
#[test]
fn prop_reject_dot_names() {
    let base = Path::new("/tmp/pool");
    assert!(safe_join_under(base, OsStr::new(".")).is_none());
    assert!(safe_join_under(base, OsStr::new("..")).is_none());
    assert!(safe_join_under(base, OsStr::new("")).is_none());
    assert!(deb_pool_dest(OsStr::new("..")).is_none());
    assert!(rpm_pool_dest(OsStr::new(".")).is_none());
}

/// Sweep destinations always land under the expected pool prefix.
#[test]
fn prop_sweep_dest_prefix() {
    let mut rng = Rng::new(0xBA5E_0003);
    for _ in 0..CASES {
        let name = safe_segment(&mut rng);
        let deb = format!("{name}.deb");
        let rpm = format!("{name}.rpm");
        let d = package_sweep_dest(OsStr::new(&deb), "deb").expect("deb");
        let r = package_sweep_dest(OsStr::new(&rpm), "rpm").expect("rpm");
        assert!(d.starts_with("apt/pool/main"));
        assert!(r.starts_with("rpm/pool"));
        assert_eq!(&d, &deb_pool_dest(OsStr::new(&deb)).expect("deb dest"));
        assert_eq!(&r, &rpm_pool_dest(OsStr::new(&rpm)).expect("rpm dest"));
        assert!(package_sweep_dest(OsStr::new(&deb), "txt").is_none());
        assert!(is_under_base(Path::new("apt/pool/main"), &d));
        assert!(is_under_base(Path::new("rpm/pool"), &r));
    }
}

/// Absolute-looking single segments on Unix start with `/` only if the
/// whole string is absolute — `safe_join_under` rejects absolute paths.
#[test]
fn prop_reject_absolute_unix() {
    let mut rng = Rng::new(0xBA5E_0004);
    for _ in 0..CASES {
        let rest = safe_segment(&mut rng);
        let base = Path::new("/var/lib/pool");
        let abs = format!("/{rest}");
        // On Unix Path::new("/foo").is_absolute() is true.
        assert!(safe_join_under(base, OsStr::new(&abs)).is_none());
        assert!(package_sweep_dest(OsStr::new(&abs), "deb").is_none());
    }
}
