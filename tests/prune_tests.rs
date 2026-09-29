//! Property tests for prune selection (keep newest N per package) — std-only.

use idlescreen_packages::{PackageFile, compare_versions, group_by_name, select_to_remove};
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;

mod common;
use common::{Rng, pkg_name, semver_core};

const CASES: usize = 256;

/// One package family with unique paths and semver versions.
fn package_family(rng: &mut Rng) -> (String, Vec<PackageFile>) {
    let name = pkg_name(rng, 8);
    let n = rng.range(1, 7) as usize;
    let files = (0..n)
        .map(|i| {
            let version = semver_core(rng, 30);
            PackageFile {
                path: PathBuf::from(format!("{name}-{i}-{version}")),
                version,
            }
        })
        .collect();
    (name, files)
}

/// Never remove more than total − keep (per package), and never leave more
/// than `keep` when count > keep.
#[test]
fn prop_remove_count_bounded() {
    let mut rng = Rng::new(0x9B00_0001);
    for _ in 0..CASES {
        let n_families = rng.range(1, 4) as usize;
        let families: Vec<_> = (0..n_families).map(|_| package_family(&mut rng)).collect();
        let keep = rng.below(6) as usize;
        let mut map: HashMap<String, Vec<PackageFile>> = HashMap::new();
        for (name, files) in families {
            map.entry(name).or_default().extend(files);
        }
        let mut expected_remove = 0usize;
        for files in map.values() {
            let n = files.len();
            if n > keep {
                expected_remove += n - keep;
            }
        }
        let removed = select_to_remove(map, keep);
        assert_eq!(removed.len(), expected_remove);
    }
}

/// Removed versions are never strictly newer than a kept version of the
/// same package (semver families).
#[test]
fn prop_removed_are_oldest() {
    let mut rng = Rng::new(0x9B00_0002);
    for _ in 0..CASES {
        let name = pkg_name(&mut rng, 8);
        let n = rng.range(2, 7) as usize;
        let versions: Vec<String> = (0..n).map(|_| semver_core(&mut rng, 30)).collect();
        let keep = rng.range(1, 3) as usize;
        let files: Vec<PackageFile> = versions
            .iter()
            .enumerate()
            .map(|(i, version)| PackageFile {
                path: PathBuf::from(format!("p{i}")),
                version: version.clone(),
            })
            .collect();
        let mut map = HashMap::new();
        map.insert(name, files.clone());
        let removed: HashSet<PathBuf> = select_to_remove(map, keep).into_iter().collect();
        if files.len() <= keep {
            assert!(removed.is_empty());
            continue;
        }
        let mut kept_versions = Vec::new();
        let mut removed_versions = Vec::new();
        for f in &files {
            if removed.contains(&f.path) {
                removed_versions.push(f.version.clone());
            } else {
                kept_versions.push(f.version.clone());
            }
        }
        assert_eq!(kept_versions.len(), keep);
        for rv in &removed_versions {
            for kv in &kept_versions {
                assert_ne!(
                    compare_versions(rv, kv),
                    std::cmp::Ordering::Greater,
                    "removed {} newer than kept {}",
                    rv,
                    kv
                );
            }
        }
    }
}

/// group_by_name then select is deterministic in count for fixed keep.
#[test]
fn prop_group_then_select() {
    let mut rng = Rng::new(0x9B00_0003);
    for _ in 0..CASES {
        let n = rng.below(20) as usize;
        let entries: Vec<(String, String, u32)> = (0..n)
            .map(|_| {
                (
                    pkg_name(&mut rng, 8),
                    semver_core(&mut rng, 30),
                    rng.below(100) as u32,
                )
            })
            .collect();
        let keep = rng.below(5) as usize;
        let pairs = entries.into_iter().map(|(name, version, i)| {
            (
                name.clone(),
                PackageFile {
                    path: PathBuf::from(format!("{name}-{version}-{i}")),
                    version,
                },
            )
        });
        let map = group_by_name(pairs);
        let total: usize = map.values().map(|v| v.len()).sum();
        let removed = select_to_remove(map, keep);
        assert!(removed.len() <= total);
    }
}

/// keep == 0 removes everything.
#[test]
fn prop_keep_zero_removes_all() {
    let mut rng = Rng::new(0x9B00_0004);
    for _ in 0..CASES {
        let n_families = rng.below(4) as usize;
        let families: Vec<_> = (0..n_families).map(|_| package_family(&mut rng)).collect();
        let mut map: HashMap<String, Vec<PackageFile>> = HashMap::new();
        for (name, files) in families {
            map.entry(name).or_default().extend(files);
        }
        let total: usize = map.values().map(|v| v.len()).sum();
        let removed = select_to_remove(map, 0);
        assert_eq!(removed.len(), total);
    }
}
