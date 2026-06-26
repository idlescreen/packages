#!/usr/bin/env cargo
//! ```cargo
//! [dependencies]
//! ```

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

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("==========================================");
    println!("Updating UberMetroid Packages Repository (stable/main) via Rust...");
    println!("==========================================");

    fs::create_dir_all("pool/main")?;
    fs::create_dir_all("dists/stable/main/binary-amd64")?;

    // Sweep loose .deb files from root to pool/main
    if let Ok(entries) = fs::read_dir(".") {
        for entry in entries {
            let entry = entry?;
            let path = entry.path();
            if path.is_file() && path.extension().and_then(|s| s.to_str()) == Some("deb") {
                let dest = Path::new("pool/main").join(path.file_name().unwrap());
                println!("-> Sweeping loose package: {:?}", path.file_name().unwrap());
                fs::rename(&path, &dest)?;
            }
        }
    }

    // 1. Generate APT metadata
    println!("Generating APT metadata...");
    
    // Scan pool/main and output Packages index
    let packages_path = "dists/stable/main/binary-amd64/Packages";
    let packages_file = fs::File::create(packages_path)?;
    run_cmd(Command::new("dpkg-scanpackages")
        .args(["--multiversion", "pool/main"])
        .stdout(packages_file))?;

    // Compress Packages file
    run_cmd(Command::new("gzip")
        .args(["-k", "-f", packages_path]))?;

    // Generate Release file
    let release_path = "dists/stable/Release";
    let release_file = fs::File::create(release_path)?;
    run_cmd(Command::new("apt-ftparchive")
        .args([
            "-o", "APT::FTPArchive::Release::Origin=ubermetroid",
            "-o", "APT::FTPArchive::Release::Label=ubermetroid",
            "-o", "APT::FTPArchive::Release::Suite=stable",
            "-o", "APT::FTPArchive::Release::Codename=stable",
            "-o", "APT::FTPArchive::Release::Architectures=amd64",
            "-o", "APT::FTPArchive::Release::Components=main",
            "-o", "APT::FTPArchive::Release::Description=UberMetroid APT Repository (stable/main)",
            "release", "dists/stable"
        ])
        .stdout(release_file))?;

    // Sign Release file
    let signing_key = "jerydleuck@gmail.com";
    let key_check = Command::new("gpg")
        .args(["--list-secret-keys", signing_key])
        .output();

    if let Ok(output) = key_check {
        if output.status.success() {
            // Delete old signatures
            let _ = fs::remove_file("dists/stable/Release.gpg");
            let _ = fs::remove_file("dists/stable/InRelease");

            run_cmd(Command::new("gpg")
                .args(["--batch", "--yes", "--default-key", signing_key, "-abs", "-o", "dists/stable/Release.gpg", "dists/stable/Release"]))?;
            run_cmd(Command::new("gpg")
                .args(["--batch", "--yes", "--default-key", signing_key, "--clearsign", "-o", "dists/stable/InRelease", "dists/stable/Release"]))?;
            println!("Signed Release files successfully.");
        } else {
            println!("Warning: GPG signing key not found, skipping Release signatures.");
        }
    } else {
        println!("Warning: Could not run gpg to check keys.");
    }

    println!("==========================================");
    println!("Update complete!");
    println!("==========================================");

    Ok(())
}
