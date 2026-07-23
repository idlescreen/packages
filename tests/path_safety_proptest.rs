//! Property tests for pool path construction and path-safety.
// SPDX-License-Identifier: Apache-2.0

use crateria_packages::{
    deb_pool_dest, is_under_base, package_sweep_dest, rpm_pool_dest, safe_join_under,
};
use proptest::prelude::*;
use std::ffi::OsStr;
use std::path::{Path, PathBuf};

fn safe_segment() -> impl Strategy<Value = String> {
    prop::string::string_regex("[A-Za-z0-9][A-Za-z0-9._+-]{0,24}").expect("seg")
}

proptest! {
    /// Safe single-segment names join under base and stay under base.
    #[test]
    fn prop_safe_join_under_base(
        base_segs in prop::collection::vec(safe_segment(), 1..4),
        file in safe_segment(),
    ) {
        let mut base = PathBuf::new();
        for s in &base_segs {
            base.push(s);
        }
        let out = safe_join_under(&base, OsStr::new(&file))
            .expect("safe segment must join");
        prop_assert!(is_under_base(&base, &out));
        prop_assert_eq!(out, base.join(&file));
    }
}

proptest! {
    /// Names with `/` or `\\` are always rejected.
    #[test]
    fn prop_reject_separators(
        left in safe_segment(),
        right in safe_segment(),
    ) {
        let base = Path::new("pool");
        let slash = format!("{left}/{right}");
        let back = format!("{left}\\{right}");
        prop_assert!(safe_join_under(base, OsStr::new(&slash)).is_none());
        prop_assert!(safe_join_under(base, OsStr::new(&back)).is_none());
    }
}

proptest! {
    /// `.` and `..` and empty are rejected.
    #[test]
    fn prop_reject_dot_names(_y in 0u8..1) {
        let base = Path::new("/tmp/pool");
        prop_assert!(safe_join_under(base, OsStr::new(".")).is_none());
        prop_assert!(safe_join_under(base, OsStr::new("..")).is_none());
        prop_assert!(safe_join_under(base, OsStr::new("")).is_none());
    }
}

proptest! {
    /// Sweep destinations always land under the expected pool prefix.
    #[test]
    fn prop_sweep_dest_prefix(name in safe_segment()) {
        let deb = format!("{name}.deb");
        let rpm = format!("{name}.rpm");
        let d = package_sweep_dest(OsStr::new(&deb), "deb").expect("deb");
        let r = package_sweep_dest(OsStr::new(&rpm), "rpm").expect("rpm");
        prop_assert!(d.starts_with("apt/pool/main"));
        prop_assert!(r.starts_with("rpm/pool"));
        prop_assert_eq!(d, deb_pool_dest(OsStr::new(&deb)));
        prop_assert_eq!(r, rpm_pool_dest(OsStr::new(&rpm)));
        prop_assert!(package_sweep_dest(OsStr::new(&deb), "txt").is_none());
    }
}

proptest! {
    /// Absolute-looking single segments on Unix start with `/` only if the
    /// whole string is absolute — `safe_join_under` rejects absolute paths.
    #[test]
    fn prop_reject_absolute_unix(rest in safe_segment()) {
        let base = Path::new("/var/lib/pool");
        let abs = format!("/{rest}");
        // On Unix Path::new("/foo").is_absolute() is true.
        prop_assert!(safe_join_under(base, OsStr::new(&abs)).is_none());
    }
}
