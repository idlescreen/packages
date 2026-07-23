//! Rebuild APT and RPM repository indexes and sign metadata.
// SPDX-License-Identifier: Apache-2.0

use crateria_packages::sign_macros::{resolve_gpg_bin, resolve_signing_key};
use crateria_packages::sweep::sweep_loose_packages;
use std::fs;
use std::path::Path;
use std::process::Command;

fn run_cmd(cmd: &mut Command) -> Result<(), String> {
    let status = cmd.status().map_err(|e| e.to_string())?;
    if !status.success() {
        return Err(format!("Command failed with exit status: {status}"));
    }
    Ok(())
}

fn dearmor_key() -> Result<(), String> {
    println!("Regenerating binary GPG keyring...");
    let gpg_file = fs::File::create("apt/crateria-keyring.gpg").map_err(|e| e.to_string())?;
    let key_file = fs::File::open("apt/crateria-key.gpg").map_err(|e| e.to_string())?;

    let status = Command::new("gpg")
        .arg("--dearmor")
        .stdin(key_file)
        .stdout(gpg_file)
        .status()
        .map_err(|e| e.to_string())?;

    if !status.success() {
        return Err(format!("gpg --dearmor failed with status: {status}"));
    }
    Ok(())
}

fn run_createrepo() -> Result<(), String> {
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
    let signing_key = resolve_signing_key(
        std::env::var("CRATERIA_GPG_NAME").ok().as_deref(),
        "jerydleuck@gmail.com",
    );
    let gpg_bin = resolve_gpg_bin(std::env::var("CRATERIA_GPG_BIN").ok().as_deref());
    if !Path::new("rpm/repodata/repomd.xml").exists() {
        return Ok(());
    }
    println!("Signing RPM repomd.xml...");
    let key_check = Command::new(&gpg_bin)
        .args(["--list-secret-keys", &signing_key])
        .output();
    let Ok(output) = key_check else {
        return Err(format!(
            "Could not run {gpg_bin} to check keys; refusing unsigned RPM metadata"
        ));
    };
    if !output.status.success() {
        return Err(format!(
            "GPG signing key '{signing_key}' not found; refusing to publish unsigned RPM metadata"
        ));
    }
    let _ = fs::remove_file("rpm/repodata/repomd.xml.asc");
    run_cmd(
        Command::new(&gpg_bin)
            .args([
                "--batch",
                "--yes",
                "--default-key",
                &signing_key,
                "--detach-sign",
                "--armor",
                "repodata/repomd.xml",
            ])
            .current_dir("rpm"),
    )?;
    println!("Signed RPM repomd.xml successfully.");
    Ok(())
}

/// Returns Ok(true) if Release was signed; Ok(false) if key missing (caller may stop).
fn sign_apt_release(signing_key: &str, gpg_bin: &str) -> Result<bool, String> {
    let key_check = Command::new(gpg_bin)
        .args(["--list-secret-keys", signing_key])
        .output()
        .map_err(|e| format!("Could not run {gpg_bin} to check keys: {e}"))?;

    if !key_check.status.success() {
        println!(
            "GPG signing key '{signing_key}' not found; skipping GPG signing of APT Release"
        );
        return Ok(false);
    }

    let _ = fs::remove_file("apt/dists/stable/Release.gpg");
    let _ = fs::remove_file("apt/dists/stable/InRelease");

    run_cmd(
        Command::new(gpg_bin)
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
        Command::new(gpg_bin)
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
    Ok(true)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("==========================================");
    println!("Updating crateria Packages Repository (stable/main) via Rust...");
    println!("==========================================");

    fs::create_dir_all("apt/pool/main")?;
    fs::create_dir_all("apt/dists/stable/main/binary-amd64")?;
    fs::create_dir_all("rpm/pool")?;

    sweep_loose_packages(Path::new("."))?;
    dearmor_key()?;

    println!("Generating APT metadata...");
    let packages_path = "apt/dists/stable/main/binary-amd64/Packages";
    let packages_file = fs::File::create(packages_path)?;
    run_cmd(
        Command::new("dpkg-scanpackages")
            .args(["--multiversion", "pool/main"])
            .stdout(packages_file)
            .current_dir("apt"),
    )?;

    run_cmd(
        Command::new("gzip")
            .args(["-k", "-f", "dists/stable/main/binary-amd64/Packages"])
            .current_dir("apt"),
    )?;

    let release_path = "apt/dists/stable/Release";
    let release_file = fs::File::create(release_path)?;
    run_cmd(
        Command::new("apt-ftparchive")
            .args([
                "-o",
                "APT::FTPArchive::Release::Origin=crateria",
                "-o",
                "APT::FTPArchive::Release::Label=crateria",
                "-o",
                "APT::FTPArchive::Release::Suite=stable",
                "-o",
                "APT::FTPArchive::Release::Codename=stable",
                "-o",
                "APT::FTPArchive::Release::Architectures=amd64",
                "-o",
                "APT::FTPArchive::Release::Components=main",
                "-o",
                "APT::FTPArchive::Release::Description=crateria APT Repository (stable/main)",
                "release",
                "dists/stable",
            ])
            .stdout(release_file)
            .current_dir("apt"),
    )?;

    let signing_key = resolve_signing_key(
        std::env::var("CRATERIA_GPG_NAME").ok().as_deref(),
        "jerydleuck@gmail.com",
    );
    let gpg_bin = resolve_gpg_bin(std::env::var("CRATERIA_GPG_BIN").ok().as_deref());
    if !sign_apt_release(&signing_key, &gpg_bin)? {
        // Preserve historical fail-open: stop after APT index without RPM steps
        // when the signing key is unavailable.
        return Ok(());
    }

    run_createrepo()?;
    sign_rpm_metadata()?;

    println!("==========================================");
    println!("Update complete!");
    println!("==========================================");

    Ok(())
}
