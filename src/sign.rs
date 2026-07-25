//! Sign all RPMs in the pool and refresh repository metadata.
// SPDX-License-Identifier: Apache-2.0

use idlescreen_packages::paths::{is_rpm_path, safe_join_under};
use idlescreen_packages::sign_macros::{
    build_rpmmacros, resolve_gpg_bin_from_env, resolve_gpg_name_from_env, resolve_gpg_path_from_env,
    skip_rpm_sign_install_from_env,
};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

fn run_cmd(cmd: &mut Command) -> Result<(), String> {
    let status = cmd.status().map_err(|e| e.to_string())?;
    if !status.success() {
        return Err(format!(
            "Command failed with exit status: {:?}",
            status.code()
        ));
    }
    Ok(())
}

fn command_exists(name: &str) -> bool {
    Command::new("which")
        .arg(name)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// Collect `.rpm` paths under `pool`, joining only safe bare filenames.
fn collect_rpms(pool: &Path) -> Result<Vec<PathBuf>, String> {
    let mut rpms = Vec::new();
    if !pool.exists() {
        return Ok(rpms);
    }
    for entry in fs::read_dir(pool).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let path = entry.path();
        if !path.is_file() || !is_rpm_path(&path) {
            continue;
        }
        let Some(name) = path.file_name() else {
            continue;
        };
        // Re-join via safe_join_under so path traversal names are skipped.
        // Prefer the re-joined path so callers only see base-constrained paths.
        if let Some(safe) = safe_join_under(pool, name) {
            rpms.push(safe);
        }
    }
    Ok(rpms)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let gpg_name = match resolve_gpg_name_from_env() {
        Some(val) => val,
        None => {
            eprintln!(
                "ERROR: IDLESCREEN_GPG_NAME (or legacy CRATERIA_GPG_NAME) is unset or invalid.\n\n\
                 Export the signing identity (email or exact uid string), for example:\n\
                 \texport IDLESCREEN_GPG_NAME='packages@example.com'\n\
                 \t# optional:\n\
                 \texport IDLESCREEN_GPG_PATH=\"$HOME/.gnupg\"\n\
                 \texport IDLESCREEN_GPG_BIN=gpg\n\
                 \t# legacy aliases CRATERIA_GPG_* still work\n\
                 \tcargo run --release --bin sign\n\n\
                 See AGENT.md signing SOP and the import-release workflow."
            );
            std::process::exit(1);
        }
    };

    let gpg_bin = resolve_gpg_bin_from_env();
    let gpg_path = resolve_gpg_path_from_env();
    let skip_install = skip_rpm_sign_install_from_env();

    if !command_exists("rpmsign") {
        if skip_install {
            eprintln!(
                "ERROR: rpmsign not found and IDLESCREEN_SKIP_RPM_SIGN_INSTALL (or CRATERIA_*) is set."
            );
            std::process::exit(1);
        }
        if command_exists("dnf") {
            println!("Installing rpm-sign...");
            // Manual validation rule: do not use -y or --assumeyes in package manager commands.
            run_cmd(Command::new("sudo").args(["dnf", "install", "rpm-sign"]))?;
        } else {
            eprintln!(
                "ERROR: rpmsign not found. Install rpm-sign (or rpm-sign package) and retry."
            );
            std::process::exit(1);
        }
    }

    let mut gpg_check = Command::new(&gpg_bin);
    if let Some(ref path) = gpg_path {
        gpg_check.args(["--homedir", path]);
    }
    gpg_check.args(["--list-secret-keys", &gpg_name]);
    let status = gpg_check
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()?;

    if !status.success() {
        eprintln!(
            "ERROR: No GPG secret key found for: {}\n\
             Import the signing key into this environment first, for example:\n\
             \t{} {} --import /path/to/private-key.asc",
            gpg_name,
            gpg_bin,
            if let Some(ref path) = gpg_path {
                format!("--homedir {path}")
            } else {
                String::new()
            }
        );
        std::process::exit(1);
    }

    let home = env::var("HOME")?;
    let rpmmacros_path = PathBuf::from(&home).join(".rpmmacros");
    let macros_content = build_rpmmacros(&gpg_name, &gpg_bin, gpg_path.as_deref());
    fs::write(&rpmmacros_path, macros_content)?;
    println!(
        "Wrote {} for identity: {}",
        rpmmacros_path.display(),
        gpg_name
    );

    let rpm_pool = Path::new("rpm/pool");
    let rpms = collect_rpms(rpm_pool)?;
    if rpms.is_empty() {
        eprintln!("ERROR: no RPMs under rpm/pool/");
        std::process::exit(1);
    }

    println!("Signing {} RPM package(s) in rpm/pool/...", rpms.len());
    let mut sign_cmd = Command::new("rpmsign");
    sign_cmd.arg("--resign");
    for rpm in &rpms {
        sign_cmd.arg(rpm);
    }
    run_cmd(&mut sign_cmd)?;

    println!("Rebuilding and signing repository metadata...");
    run_cmd(Command::new("cargo").args(["run", "--release", "--bin", "update"]))?;

    println!("==========================================================");
    println!("Signed packages and updated repository metadata.");
    println!("Review, commit, and push, then consumers can:");
    println!("  sudo dnf clean all && sudo dnf upgrade");
    println!("==========================================================");

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn collect_rpms_filters_extension() {
        let n = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let dir = env::temp_dir().join(format!("idlescreen-sign-rpms-{n}"));
        fs::create_dir_all(&dir).expect("mkdir");
        fs::write(dir.join("a.rpm"), b"r").expect("rpm");
        fs::write(dir.join("b.deb"), b"d").expect("deb");
        fs::write(dir.join("notes.txt"), b"t").expect("txt");
        let found = collect_rpms(&dir).expect("collect");
        assert_eq!(found.len(), 1);
        assert!(found[0].ends_with("a.rpm"));
        // Returned path is the safe re-join under the pool base.
        assert_eq!(found[0], dir.join("a.rpm"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn collect_rpms_missing_dir() {
        let dir = env::temp_dir().join("idlescreen-sign-missing-noexist");
        let _ = fs::remove_dir_all(&dir);
        assert!(collect_rpms(&dir).expect("ok").is_empty());
    }

    #[test]
    fn collect_rpms_returns_paths_under_pool() {
        let n = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let dir = env::temp_dir().join(format!("idlescreen-sign-under-{n}"));
        fs::create_dir_all(&dir).expect("mkdir");
        fs::write(dir.join("pkg-1.0-1.x86_64.rpm"), b"r").expect("rpm");
        let found = collect_rpms(&dir).expect("collect");
        assert_eq!(found.len(), 1);
        assert!(
            found[0].starts_with(&dir),
            "signed path must stay under pool: {:?}",
            found[0]
        );
        let _ = fs::remove_dir_all(&dir);
    }
}
