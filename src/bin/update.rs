// SPDX-License-Identifier: Apache-2.0

//! `update` binary: top-level orchestrator for the package repository.
//! Each step lives in its own page under `update_steps::*`. This file is just the entry: print the banner,
//! create the directory skeleton, then call the steps in the order
//! the publish contract requires.

use std::fs;
use std::path::Path;

use idlescreen_packages::sign_macros::{
    resolve_gpg_bin_from_env, resolve_gpg_name_from_env, resolve_signing_key,
};
use idlescreen_packages::sweep::sweep_loose_packages;
use idlescreen_packages::update_steps::{
    dearmor_key, run_createrepo, sign_apt_release, sign_rpm_metadata, sign_rpms,
};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("==========================================");
    println!("Updating IdleScreen Packages Repository (stable/main) via Rust...");
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
        std::process::Command::new("dpkg-scanpackages")
            .args(["--multiversion", "pool/main"])
            .stdout(packages_file)
            .current_dir("apt"),
    )?;

    run_cmd(
        std::process::Command::new("gzip")
            .args(["-k", "-f", "dists/stable/main/binary-amd64/Packages"])
            .current_dir("apt"),
    )?;

    let release_path = "apt/dists/stable/Release";
    let release_file = fs::File::create(release_path)?;
    run_cmd(
        std::process::Command::new("apt-ftparchive")
            .args([
                "-o",
                "APT::FTPArchive::Release::Origin=IdleScreen",
                "-o",
                "APT::FTPArchive::Release::Label=IdleScreen",
                "-o",
                "APT::FTPArchive::Release::Suite=stable",
                "-o",
                "APT::FTPArchive::Release::Codename=stable",
                "-o",
                "APT::FTPArchive::Release::Architectures=amd64",
                "-o",
                "APT::FTPArchive::Release::Components=main",
                "-o",
                "APT::FTPArchive::Release::Description=IdleScreen APT Repository (stable/main)",
                "release",
                "dists/stable",
            ])
            .stdout(release_file)
            .current_dir("apt"),
    )?;

    let signing_key = resolve_signing_key(
        resolve_gpg_name_from_env().as_deref(),
        "jerydleuck@gmail.com",
    );
    let gpg_bin = resolve_gpg_bin_from_env();
    sign_apt_release(&signing_key, &gpg_bin)?;

    sign_rpms()?;
    run_createrepo()?;
    sign_rpm_metadata()?;

    println!("==========================================");
    println!("Update complete!");
    println!("==========================================");

    Ok(())
}

/// Local copy of the `run_cmd` helper used here. Kept private to
/// the binary so the per-step library files don't need to re-export
/// it just for this orchestrator.
fn run_cmd(cmd: &mut std::process::Command) -> Result<(), Box<dyn std::error::Error>> {
    let status = cmd.status()?;
    if !status.success() {
        return Err(format!("Command failed with exit status: {status}").into());
    }
    Ok(())
}
