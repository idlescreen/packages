//! Move loose package files from a root directory into apt/rpm pools.
// SPDX-License-Identifier: Apache-2.0

use crate::paths::package_sweep_dest;
use std::fs;
use std::path::Path;

/// Move loose `.deb`/`.rpm` files from `root` into their pools.
///
/// Destinations are `apt/pool/main/<name>` and `rpm/pool/<name>` relative to
/// `root` (or to the process CWD when `root` is `"."`).
pub fn sweep_loose_packages(root: &Path) -> Result<usize, String> {
    let mut moved = 0usize;
    let entries = match fs::read_dir(root) {
        Ok(e) => e,
        Err(_) => return Ok(0),
    };
    for entry in entries {
        let entry = entry.map_err(|e| e.to_string())?;
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let Some(ext) = path.extension().and_then(|s| s.to_str()) else {
            continue;
        };
        let Some(name) = path.file_name() else {
            continue;
        };
        let Some(dest) = package_sweep_dest(name, ext) else {
            continue;
        };
        let dest = if root == Path::new(".") {
            dest
        } else {
            root.join(&dest)
        };
        println!("-> Sweeping loose package: {name:?}");
        fs::rename(&path, &dest).map_err(|e| e.to_string())?;
        moved += 1;
    }
    Ok(moved)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn sweep_moves_deb_and_rpm() {
        let n = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let root = env::temp_dir().join(format!("crateria-sweep-{n}"));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("apt/pool/main")).expect("apt");
        fs::create_dir_all(root.join("rpm/pool")).expect("rpm");
        fs::write(root.join("foo_1.0_amd64.deb"), b"d").expect("deb");
        fs::write(root.join("bar-1.0-1.x86_64.rpm"), b"r").expect("rpm");
        fs::write(root.join("readme.txt"), b"t").expect("txt");

        let moved = sweep_loose_packages(&root).expect("sweep");
        assert_eq!(moved, 2);
        assert!(!root.join("foo_1.0_amd64.deb").exists());
        assert!(root.join("apt/pool/main/foo_1.0_amd64.deb").exists());
        assert!(root.join("rpm/pool/bar-1.0-1.x86_64.rpm").exists());
        assert!(root.join("readme.txt").exists());
        let _ = fs::remove_dir_all(&root);
    }
}
