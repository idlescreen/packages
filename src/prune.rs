//! Prune old package versions from apt and rpm pools.
// SPDX-License-Identifier: Apache-2.0

use crateria_packages::package_parse::{parse_deb_filename, parse_rpm_filename};
use crateria_packages::prune_core::{group_by_name, select_to_remove, PackageFile};
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
        let filename = match path.file_name().and_then(|s| s.to_str()) {
            Some(f) => f.to_string(),
            None => continue,
        };
        let id = if is_deb {
            parse_deb_filename(&filename)
        } else {
            parse_rpm_filename(&filename)
        };
        if let Some(id) = id {
            out.push((
                id.name,
                PackageFile {
                    path,
                    version: id.version,
                },
            ));
        }
    }
    Ok(out)
}

fn prune_directory(dir_path: &Path, keep: usize, is_deb: bool) -> Result<(), String> {
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
        let name = path
            .file_name()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_else(|| path.display().to_string());
        println!("  rm {name:?}");
        fs::remove_file(path).map_err(|e| e.to_string())?;
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
    let keep = match parse_keep_arg(&args) {
        Ok(k) => k,
        Err(msg) => {
            eprintln!("{msg}");
            std::process::exit(1);
        }
    };

    prune_directory(Path::new("apt/pool/main"), keep, true)?;
    prune_directory(Path::new("rpm/pool"), keep, false)?;

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
        let dir = env::temp_dir().join(format!("crateria-prune-{label}-{n}"));
        fs::create_dir_all(&dir).expect("create temp");
        dir
    }

    #[test]
    fn parse_keep_default_and_value() {
        assert_eq!(parse_keep_arg(&["prune".into()]).expect("default"), 3);
        assert_eq!(
            parse_keep_arg(&["prune".into(), "5".into()]).expect("5"),
            5
        );
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
        prune_directory(&dir, 1, true).expect("prune");
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
        let dir = env::temp_dir().join("crateria-prune-missing-noexist");
        let _ = fs::remove_dir_all(&dir);
        prune_directory(&dir, 3, true).expect("missing ok");
    }
}
