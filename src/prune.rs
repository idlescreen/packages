use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

fn split_parts(s: &str) -> Vec<String> {
    let mut parts = Vec::new();
    let mut current = String::new();
    for c in s.chars() {
        if c.is_alphanumeric() {
            current.push(c);
        } else {
            if !current.is_empty() {
                parts.push(current.clone());
                current.clear();
            }
        }
    }
    if !current.is_empty() {
        parts.push(current);
    }
    parts
}

fn compare_versions(a: &str, b: &str) -> std::cmp::Ordering {
    let a_parts = split_parts(a);
    let b_parts = split_parts(b);
    for (ap, bp) in a_parts.iter().zip(b_parts.iter()) {
        match (ap.parse::<u64>(), bp.parse::<u64>()) {
            (Ok(an), Ok(bn)) => {
                if an != bn {
                    return an.cmp(&bn);
                }
            }
            _ => {
                if ap != bp {
                    return ap.cmp(bp);
                }
            }
        }
    }
    a_parts.len().cmp(&b_parts.len())
}

// Wrapper structure to sort files by version
struct PackageFile {
    path: PathBuf,
    version: String,
}

fn prune_directory(
    dir_path: &Path,
    keep: usize,
    is_deb: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    if !dir_path.exists() {
        return Ok(());
    }

    println!(
        "Pruning {:?} — keeping latest {} versions of each package...",
        dir_path, keep
    );

    // Group files by package name
    let mut packages: HashMap<String, Vec<PackageFile>> = HashMap::new();

    for entry in fs::read_dir(dir_path)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_file() {
            let filename = path.file_name().unwrap().to_string_lossy().to_string();

            if is_deb && filename.ends_with(".deb") {
                // Format: name_version_arch.deb
                let parts: Vec<&str> = filename.split('_').collect();
                if parts.len() >= 2 {
                    let name = parts[0].to_string();
                    let version = parts[1].to_string();
                    packages
                        .entry(name)
                        .or_default()
                        .push(PackageFile { path, version });
                }
            } else if !is_deb && filename.ends_with(".rpm") {
                // Format: name-version-release.arch.rpm
                let name_without_ext = filename.strip_suffix(".rpm").unwrap();
                let parts: Vec<&str> = name_without_ext.split('-').collect();
                if parts.len() >= 3 {
                    let version = parts[parts.len() - 2].to_string();
                    let name = parts[0..parts.len() - 2].join("-");
                    packages
                        .entry(name)
                        .or_default()
                        .push(PackageFile { path, version });
                }
            }
        }
    }

    let mut removed = 0;
    let mut kept = 0;

    for (_pkg, mut files) in packages {
        // Sort files by parsed version
        files.sort_by(|a, b| compare_versions(&a.version, &b.version));

        let count = files.len();
        if count <= keep {
            kept += count;
            continue;
        }

        // Delete the oldest ones
        let delete_count = count - keep;
        for file in files.iter().take(delete_count) {
            println!("  rm {:?}", file.path.file_name().unwrap());
            fs::remove_file(&file.path)?;
            removed += 1;
        }
        kept += keep;
    }

    println!("Pruned {} files; kept {} in {:?}", removed, kept, dir_path);
    Ok(())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    let mut keep = 3;

    if args.len() > 1 {
        if let Ok(k) = args[1].parse::<usize>() {
            keep = k;
        } else {
            eprintln!("Error: KEEP must be a positive integer (got: {})", args[1]);
            std::process::exit(1);
        }
    }

    prune_directory(Path::new("apt/pool/main"), keep, true)?;
    prune_directory(Path::new("rpm/pool"), keep, false)?;

    println!("\nNext: regenerate the repository indices with: cargo run --bin update");
    Ok(())
}
