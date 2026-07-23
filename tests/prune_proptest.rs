//! Property tests for prune selection (keep newest N per package).
// SPDX-License-Identifier: Apache-2.0

use crateria_packages::{compare_versions, group_by_name, select_to_remove, PackageFile};
use proptest::prelude::*;
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;

fn semver_core() -> impl Strategy<Value = String> {
    (0u64..30, 0u64..30, 0u64..30).prop_map(|(a, b, c)| format!("{a}.{b}.{c}"))
}

fn pkg_name() -> impl Strategy<Value = String> {
    prop::string::string_regex("[a-z][a-z0-9]{0,8}").expect("name")
}

/// One package family with unique paths and semver versions.
fn package_family() -> impl Strategy<Value = (String, Vec<PackageFile>)> {
    (
        pkg_name(),
        prop::collection::vec(semver_core(), 1..8),
    )
        .prop_map(|(name, versions)| {
            let files: Vec<PackageFile> = versions
                .into_iter()
                .enumerate()
                .map(|(i, version)| PackageFile {
                    path: PathBuf::from(format!("{name}-{i}-{version}")),
                    version,
                })
                .collect();
            (name, files)
        })
}

proptest! {
    /// Never remove more than total − keep (per package), and never leave more
    /// than `keep` when count > keep.
    #[test]
    fn prop_remove_count_bounded(
        families in prop::collection::vec(package_family(), 1..5),
        keep in 0usize..6,
    ) {
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
        prop_assert_eq!(removed.len(), expected_remove);
    }
}

proptest! {
    /// Removed versions are never strictly newer than a kept version of the
    /// same package (semver families).
    #[test]
    fn prop_removed_are_oldest(
        name in pkg_name(),
        versions in prop::collection::vec(semver_core(), 2..8),
        keep in 1usize..4,
    ) {
        let files: Vec<PackageFile> = versions
            .iter()
            .enumerate()
            .map(|(i, version)| PackageFile {
                path: PathBuf::from(format!("p{i}")),
                version: version.clone(),
            })
            .collect();
        let mut by_path: HashMap<PathBuf, String> = HashMap::new();
        for f in &files {
            by_path.insert(f.path.clone(), f.version.clone());
        }
        let mut map = HashMap::new();
        map.insert(name, files.clone());
        let removed: HashSet<PathBuf> = select_to_remove(map, keep).into_iter().collect();
        if files.len() <= keep {
            prop_assert!(removed.is_empty());
            return Ok(());
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
        prop_assert_eq!(kept_versions.len(), keep);
        for rv in &removed_versions {
            for kv in &kept_versions {
                prop_assert_ne!(
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

proptest! {
    /// group_by_name then select is deterministic in count for fixed keep.
    #[test]
    fn prop_group_then_select(
        entries in prop::collection::vec(
            (pkg_name(), semver_core(), 0u32..100),
            0..20
        ),
        keep in 0usize..5,
    ) {
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
        prop_assert!(removed.len() <= total);
    }
}

proptest! {
    /// keep == 0 removes everything.
    #[test]
    fn prop_keep_zero_removes_all(
        families in prop::collection::vec(package_family(), 0..4),
    ) {
        let mut map: HashMap<String, Vec<PackageFile>> = HashMap::new();
        for (name, files) in families {
            map.entry(name).or_default().extend(files);
        }
        let total: usize = map.values().map(|v| v.len()).sum();
        let removed = select_to_remove(map, 0);
        prop_assert_eq!(removed.len(), total);
    }
}
