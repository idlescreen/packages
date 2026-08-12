//! Prune old package versions from apt and rpm pools.
// SPDX-License-Identifier: Apache-2.0

use idlescreen_packages::package_parse::{parse_deb_filename, parse_rpm_filename};
use idlescreen_packages::paths::{is_under_base, safe_join_under};
use idlescreen_packages::prune_core::{PackageFile, group_by_name, select_to_remove};
use std::env;
use std::fs;
use std::path::Path;
#[cfg(test)]
use std::path::PathBuf;

fn collect_packages(dir_path: &Path, is_deb: bool) -> Result<Vec<(String, PackageFile)>, String> {
    let mut out = Vec::new();
    if !dir_path.exists() {
        return Ok(out);
    }
    let entries = fs::read_dir(dir_path).map_err(|e| e.to_string())?;
    for entry in entries {
        let entry = entry.map_err(|e| e.to_string())?;
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let Some(name_os) = path.file_name() else {
            continue;
        };
        let Some(filename) = name_os.to_str() else {
            continue;
        };
        // Only track files whose name is a single safe segment under the pool.
        let Some(safe_path) = safe_join_under(dir_path, name_os) else {
            continue;
        };
        let id = if is_deb {
            parse_deb_filename(filename)
        } else {
            parse_rpm_filename(filename)
        };
        if let Some(id) = id {
            out.push((
                id.name,
                PackageFile {
                    path: safe_path,
                    version: id.version,
                },
            ));
        }
    }
    Ok(out)
}

fn prune_directory(dir_path: &Path, keep: usize, is_deb: bool, is_dry_run: bool) -> Result<(), String> {
    if !dir_path.exists() {
        return Ok(());
    }

    println!(
        "Pruning {:?} — keeping latest {} versions of each package...",
        dir_path, keep
    );

    let entries = collect_packages(dir_path, is_deb)?;
    let packages = group_by_name(entries);
    let to_remove = select_to_remove(packages, keep);

    let mut removed = 0usize;
    for path in &to_remove {
        if !is_under_base(dir_path, path) {
            return Err(format!(
                "refusing to delete path outside pool {:?}: {}",
                dir_path,
                path.display()
            ));
        }
        let name = path
            .file_name()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_else(|| path.display().to_string());
        if is_dry_run {
            println!("  [dry-run] would rm {name:?}");
        } else {
            println!("  rm {name:?}");
            fs::remove_file(path).map_err(|e| e.to_string())?;
        }
        removed += 1;
    }

    // Recount kept files (approximate: total parseable remaining).
    let remaining = collect_packages(dir_path, is_deb)?.len();
    println!(
        "Pruned {} files; kept {} in {:?}",
        removed, remaining, dir_path
    );
    Ok(())
}

fn parse_keep_arg(args: &[String]) -> Result<usize, String> {
    if args.len() <= 1 {
        return Ok(3);
    }
    args[1]
        .parse::<usize>()
        .map_err(|_| format!("Error: KEEP must be a positive integer (got: {})", args[1]))
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    let is_dry_run = args.iter().any(|arg| arg == "--dry-run");
    let filtered_args: Vec<String> = args.into_iter().filter(|arg| arg != "--dry-run").collect();
    let keep = match parse_keep_arg(&filtered_args) {
        Ok(k) => k,
        Err(msg) => {
            eprintln!("{msg}");
            std::process::exit(1);
        }
    };

    prune_directory(Path::new("apt/pool/main"), keep, true, is_dry_run)?;
    prune_directory(Path::new("rpm/pool"), keep, false, is_dry_run)?;

    println!("\nNext: regenerate the repository indices with: cargo run --bin update");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_dir(label: &str) -> PathBuf {
        let n = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let dir = env::temp_dir().join(format!("idlescreen-prune-{label}-{n}"));
        fs::create_dir_all(&dir).expect("create temp");
        dir
    }

    #[test]
    fn parse_keep_default_and_value() {
        assert_eq!(parse_keep_arg(&["prune".into()]).expect("default"), 3);
        assert_eq!(parse_keep_arg(&["prune".into(), "5".into()]).expect("5"), 5);
        assert!(parse_keep_arg(&["prune".into(), "x".into()]).is_err());
    }

    #[test]
    fn prune_keeps_newest_deb() {
        let dir = temp_dir("deb");
        for (name, ver) in [
            ("pkg_1.0.0_amd64.deb", "1.0.0"),
            ("pkg_1.1.0_amd64.deb", "1.1.0"),
            ("pkg_2.0.0_amd64.deb", "2.0.0"),
        ] {
            let _ = ver;
            fs::write(dir.join(name), b"x").expect("write");
        }
        prune_directory(&dir, 1, true, false).expect("prune");
        let left: Vec<_> = fs::read_dir(&dir)
            .expect("rd")
            .filter_map(|e| e.ok())
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .collect();
        assert_eq!(left, vec!["pkg_2.0.0_amd64.deb".to_string()]);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn prune_missing_dir_ok() {
        let dir = env::temp_dir().join("idlescreen-prune-missing-noexist");
        let _ = fs::remove_dir_all(&dir);
        prune_directory(&dir, 3, true, false).expect("missing ok");
    }

    #[test]
    fn collect_skips_unparseable_and_keeps_safe_paths() {
        let dir = temp_dir("collect");
        fs::write(dir.join("ok_1.0.0_amd64.deb"), b"x").expect("write");
        fs::write(dir.join("notes.txt"), b"t").expect("txt");
        let entries = collect_packages(&dir, true).expect("collect");
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].0, "ok");
        assert!(is_under_base(&dir, &entries[0].1.path));
        let _ = fs::remove_dir_all(&dir);
    }
}
