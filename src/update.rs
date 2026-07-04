use std::fs;
use std::path::Path;
use std::process::Command;

fn run_cmd(cmd: &mut Command) -> Result<(), String> {
    let status = cmd.status().map_err(|e| e.to_string())?;
    if !status.success() {
        return Err(format!("Command failed with exit status: {}", status));
    }
    Ok(())
}

fn dearmor_key() -> Result<(), String> {
    println!("Regenerating binary GPG keyring...");
    let gpg_file = fs::File::create("apt/ubermetroid-keyring.gpg").map_err(|e| e.to_string())?;
    let key_file = fs::File::open("apt/ubermetroid-key.gpg").map_err(|e| e.to_string())?;

    let status = Command::new("gpg")
        .arg("--dearmor")
        .stdin(key_file)
        .stdout(gpg_file)
        .status()
        .map_err(|e| e.to_string())?;

    if !status.success() {
        return Err(format!("gpg --dearmor failed with status: {}", status));
    }
    Ok(())
}

fn run_createrepo() -> Result<(), String> {
    // Check if createrepo_c is available locally
    let local_check = Command::new("which").arg("createrepo_c").output();
    let has_local = local_check.map(|o| o.status.success()).unwrap_or(false);

    if has_local {
        println!("Running createrepo_c...");
        run_cmd(
            Command::new("createrepo_c")
                .arg("--update")
                .arg(".")
                .current_dir("rpm"),
        )?;
    } else {
        // Fall back to nix-shell
        let nix_check = Command::new("which").arg("nix-shell").output();
        let has_nix = nix_check.map(|o| o.status.success()).unwrap_or(false);
        if has_nix {
            println!("Running createrepo_c via nix-shell...");
            run_cmd(
                Command::new("nix-shell")
                    .args(["-p", "createrepo_c", "--run", "createrepo_c --update ."])
                    .current_dir("rpm"),
            )?;
        } else {
            println!(
                "Warning: createrepo_c and nix-shell not found, skipping RPM repository indexing."
            );
        }
    }
    Ok(())
}

fn sign_rpm_metadata() -> Result<(), String> {
    let signing_key = "jerydleuck@gmail.com";
    if Path::new("rpm/repodata/repomd.xml").exists() {
        println!("Signing RPM repomd.xml...");
        let key_check = Command::new("gpg")
            .args(["--list-secret-keys", signing_key])
            .output();
        if let Ok(output) = key_check {
            if output.status.success() {
                let _ = fs::remove_file("rpm/repodata/repomd.xml.asc");
                run_cmd(
                    Command::new("gpg")
                        .args([
                            "--batch",
                            "--yes",
                            "--default-key",
                            signing_key,
                            "--detach-sign",
                            "--armor",
                            "repodata/repomd.xml",
                        ])
                        .current_dir("rpm"),
                )?;
                println!("Signed RPM repomd.xml successfully.");
            } else {
                println!("Warning: GPG signing key not found, skipping RPM repomd.xml signature.");
            }
        } else {
            println!("Warning: Could not run gpg to check keys.");
        }
    }
    Ok(())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("==========================================");
    println!("Updating UberMetroid Packages Repository (stable/main) via Rust...");
    println!("==========================================");

    fs::create_dir_all("apt/pool/main")?;
    fs::create_dir_all("apt/dists/stable/main/binary-amd64")?;
    fs::create_dir_all("rpm/pool")?;

    // Sweep loose files from root to respective pools
    if let Ok(entries) = fs::read_dir(".") {
        for entry in entries {
            let entry = entry?;
            let path = entry.path();
            if path.is_file() {
                let ext = path.extension().and_then(|s| s.to_str());
                if ext == Some("deb") {
                    let dest = Path::new("apt/pool/main").join(path.file_name().unwrap());
                    println!("-> Sweeping loose package: {:?}", path.file_name().unwrap());
                    fs::rename(&path, &dest)?;
                } else if ext == Some("rpm") {
                    let dest = Path::new("rpm/pool").join(path.file_name().unwrap());
                    println!("-> Sweeping loose package: {:?}", path.file_name().unwrap());
                    fs::rename(&path, &dest)?;
                }
            }
        }
    }

    // 1. Regenerate GPG keyring
    dearmor_key()?;

    // 2. Generate APT metadata
    println!("Generating APT metadata...");
    let packages_path = "apt/dists/stable/main/binary-amd64/Packages";
    let packages_file = fs::File::create(packages_path)?;
    run_cmd(
        Command::new("dpkg-scanpackages")
            .args(["--multiversion", "pool/main"])
            .stdout(packages_file)
            .current_dir("apt"),
    )?;

    // Compress Packages file
    run_cmd(
        Command::new("gzip")
            .args(["-k", "-f", "dists/stable/main/binary-amd64/Packages"])
            .current_dir("apt"),
    )?;

    // Generate Release file
    let release_path = "apt/dists/stable/Release";
    let release_file = fs::File::create(release_path)?;
    run_cmd(
        Command::new("apt-ftparchive")
            .args([
                "-o",
                "APT::FTPArchive::Release::Origin=ubermetroid",
                "-o",
                "APT::FTPArchive::Release::Label=ubermetroid",
                "-o",
                "APT::FTPArchive::Release::Suite=stable",
                "-o",
                "APT::FTPArchive::Release::Codename=stable",
                "-o",
                "APT::FTPArchive::Release::Architectures=amd64",
                "-o",
                "APT::FTPArchive::Release::Components=main",
                "-o",
                "APT::FTPArchive::Release::Description=UberMetroid APT Repository (stable/main)",
                "release",
                "dists/stable",
            ])
            .stdout(release_file)
            .current_dir("apt"),
    )?;

    // Sign Release file
    let signing_key = "jerydleuck@gmail.com";
    let key_check = Command::new("gpg")
        .args(["--list-secret-keys", signing_key])
        .output();

    if let Ok(output) = key_check {
        if output.status.success() {
            let _ = fs::remove_file("apt/dists/stable/Release.gpg");
            let _ = fs::remove_file("apt/dists/stable/InRelease");

            run_cmd(
                Command::new("gpg")
                    .args([
                        "--batch",
                        "--yes",
                        "--default-key",
                        signing_key,
                        "-abs",
                        "-o",
                        "dists/stable/Release.gpg",
                        "dists/stable/Release",
                    ])
                    .current_dir("apt"),
            )?;
            run_cmd(
                Command::new("gpg")
                    .args([
                        "--batch",
                        "--yes",
                        "--default-key",
                        signing_key,
                        "--clearsign",
                        "-o",
                        "dists/stable/InRelease",
                        "dists/stable/Release",
                    ])
                    .current_dir("apt"),
            )?;
            println!("Signed Release files successfully.");
        } else {
            println!("Warning: GPG signing key not found, skipping Release signatures.");
        }
    } else {
        println!("Warning: Could not run gpg to check keys.");
    }

    // 3. Generate RPM metadata
    run_createrepo()?;
    sign_rpm_metadata()?;

    println!("==========================================");
    println!("Update complete!");
    println!("==========================================");

    Ok(())
}
