//! Pure prune selection: which package files to delete when keeping N latest.
// SPDX-License-Identifier: Apache-2.0

use crate::version_cmp::compare_versions;
use std::collections::HashMap;
use std::path::PathBuf;

/// A package file located on disk with a parsed version string.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PackageFile {
    pub path: PathBuf,
    pub version: String,
}

/// From grouped package files, return paths that should be removed so that at
/// most `keep` newest versions remain per package name.
///
/// - If `keep == 0`, every file is selected for removal.
/// - Sorting uses [`compare_versions`]; older versions are removed first.
/// - When versions compare equal, order is stable relative to input grouping
///   (not cross-package).
pub fn select_to_remove(packages: HashMap<String, Vec<PackageFile>>, keep: usize) -> Vec<PathBuf> {
    let mut remove = Vec::new();
    for (_pkg, mut files) in packages {
        files.sort_by(|a, b| compare_versions(&a.version, &b.version));
        let count = files.len();
        if count <= keep {
            continue;
        }
        let delete_count = count - keep;
        for file in files.into_iter().take(delete_count) {
            remove.push(file.path);
        }
    }
    remove
}

/// Group `(name, PackageFile)` pairs into a map for [`select_to_remove`].
pub fn group_by_name(
    entries: impl IntoIterator<Item = (String, PackageFile)>,
) -> HashMap<String, Vec<PackageFile>> {
    let mut packages: HashMap<String, Vec<PackageFile>> = HashMap::new();
    for (name, file) in entries {
        packages.entry(name).or_default().push(file);
    }
    packages
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn pf(path: &str, version: &str) -> PackageFile {
        PackageFile {
            path: PathBuf::from(path),
            version: version.to_string(),
        }
    }

    #[test]
    fn keep_all_when_under_limit() {
        let mut m = HashMap::new();
        m.insert(
            "trance".into(),
            vec![pf("a.deb", "1.0.0"), pf("b.deb", "1.0.1")],
        );
        assert!(select_to_remove(m, 3).is_empty());
    }

    #[test]
    fn removes_oldest() {
        let mut m = HashMap::new();
        m.insert(
            "trance".into(),
            vec![
                pf("old.deb", "1.0.0"),
                pf("mid.deb", "1.1.0"),
                pf("new.deb", "2.0.0"),
            ],
        );
        let removed = select_to_remove(m, 2);
        assert_eq!(removed.len(), 1);
        assert_eq!(removed[0], Path::new("old.deb"));
    }

    #[test]
    fn keep_zero_removes_all() {
        let mut m = HashMap::new();
        m.insert("p".into(), vec![pf("a", "1"), pf("b", "2")]);
        let removed = select_to_remove(m, 0);
        assert_eq!(removed.len(), 2);
    }

    #[test]
    fn independent_packages() {
        let mut m = HashMap::new();
        m.insert(
            "a".into(),
            vec![pf("a1", "1.0.0"), pf("a2", "2.0.0"), pf("a3", "3.0.0")],
        );
        m.insert("b".into(), vec![pf("b1", "1.0.0")]);
        let removed = select_to_remove(m, 1);
        assert_eq!(removed.len(), 2);
        assert!(removed.iter().all(|p| p.to_string_lossy().starts_with('a')));
    }

    #[test]
    fn empty_map() {
        assert!(select_to_remove(HashMap::new(), 3).is_empty());
    }
}
