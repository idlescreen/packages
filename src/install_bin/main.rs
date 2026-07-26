//! IdleScreen installer — same product matrix as `install.sh`.
//! User-facing text must not overclaim.
// SPDX-License-Identifier: Apache-2.0

mod deploy;
mod host;
mod pkg;
mod ui;
mod victory;

use std::process::{Command, Stdio, exit};

use deploy::{deploy, print_deploy_result, recount, start_daemon};
use host::{desktop_label, is_apt, is_cosmic, is_dnf, os_pretty, packages, run_status};
use pkg::survey;
use ui::{
    C_BOLD, C_CYAN, C_DIM, C_GREEN, C_ORANGE, C_RESET, err, ok, pause, say, step, story_line, warn,
};
use victory::print_victory;

const REPO_BASE: &str = "https://idlescreen.github.io/packages";

fn main() {
    let arch = std::env::consts::ARCH;
    let session = std::env::var("XDG_SESSION_TYPE").unwrap_or_else(|_| "unknown".into());
    let (_de_id, de_label) = desktop_label();
    let cosmic = is_cosmic();
    let pkgs = packages(cosmic);
    let os_name = os_pretty();

    println!("\n{C_ORANGE}{C_BOLD}IdleScreen installer{C_RESET}");
    println!("{C_DIM}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{C_RESET}");
    story_line("Preparing IdleScreen for this machine…");
    pause(150);

    step("[1/5]  Scanning host identity");
    println!("  {C_DIM}os{C_RESET}       {C_GREEN}{os_name}{C_RESET}");
    println!("  {C_DIM}arch{C_RESET}     {C_GREEN}{arch}{C_RESET}");
    println!("  {C_DIM}session{C_RESET}  {C_GREEN}{session}{C_RESET}");
    println!("  {C_DIM}desktop{C_RESET}  {C_GREEN}{de_label}{C_RESET}");

    let dnf = is_dnf();
    let apt = is_apt();
    if !dnf && !apt {
        err("need DNF or APT — https://idlescreen.github.io/packages/");
        exit(1);
    }
    let channel = if dnf {
        "DNF · RPM host"
    } else {
        "APT · Debian family"
    };
    println!("  {C_DIM}packages{C_RESET} {C_GREEN}{channel}{C_RESET}");
    pause(200);

    step("[2/5]  Opening the package gate");
    setup_repo(dnf);

    step("[3/5]  Composing the install plan");
    print_plan(de_label, cosmic, &pkgs);
    let survey = survey(&pkgs, dnf);
    print_survey_summary(&survey, &pkgs);
    pause(400);

    step("[4/5]  Deploying modules into the system");
    deploy(dnf, &pkgs, &survey);
    let (present, missing) = recount(&pkgs, dnf);
    print_deploy_result(&present, &missing, pkgs.len());

    step("[5/5]  Starting the idle user service");
    let active = start_daemon();
    print_victory(
        &os_name, arch, de_label, channel, cosmic, dnf, &pkgs, &present, &missing, &survey, active,
    );
}

fn setup_repo(dnf: bool) {
    if dnf {
        story_line("Writing IdleScreen DNF repo file…");
        if !run_status(Command::new("sudo").args([
            "curl",
            "-fsSL",
            &format!("{REPO_BASE}/rpm/idlescreen.repo"),
            "-o",
            "/etc/yum.repos.d/idlescreen.repo",
        ])) {
            err("repo install failed");
            exit(1);
        }
        ok("/etc/yum.repos.d/idlescreen.repo");
        println!(
            "  {C_DIM}baseurl {REPO_BASE}/rpm · {}{C_RESET}",
            idlescreen_packages::DNF_GPG_DISCLAIMER
        );
        story_line("Refreshing IdleScreen channel metadata…");
        let _ = run_status(
            Command::new("sudo")
                .args(["dnf", "clean", "metadata", "--repo=idlescreen"])
                .stdout(Stdio::null())
                .stderr(Stdio::null()),
        );
        let meta_ok = run_status(
            Command::new("sudo")
                .args(["dnf", "makecache", "--refresh", "--repo=idlescreen"])
                .stdout(Stdio::null())
                .stderr(Stdio::null()),
        ) || run_status(
            Command::new("sudo")
                .args(["dnf", "makecache", "--refresh"])
                .stdout(Stdio::null())
                .stderr(Stdio::null()),
        );
        if meta_ok {
            ok("DNF metadata refreshed for this session");
        } else {
            warn("Could not refresh DNF metadata — install will still try the channel");
        }
        return;
    }

    story_line("Creating /etc/apt/keyrings if needed…");
    if !run_status(Command::new("sudo").args(["mkdir", "-p", "/etc/apt/keyrings"])) {
        err("mkdir /etc/apt/keyrings failed");
        exit(1);
    }
    story_line("Downloading IdleScreen APT signing keyring…");
    let key_ok = Command::new("sh")
        .arg("-c")
        .arg(format!(
            "curl -fsSL {REPO_BASE}/apt/idlescreen-keyring.gpg | sudo tee /etc/apt/keyrings/idlescreen-keyring.gpg >/dev/null"
        ))
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if !key_ok {
        err(&format!(
            "Could not download APT keyring from {REPO_BASE}/apt/idlescreen-keyring.gpg"
        ));
        exit(1);
    }
    ok("/etc/apt/keyrings/idlescreen-keyring.gpg");
    story_line("Writing APT source list (stable/main, signed-by keyring)…");
    let list_ok = Command::new("sh")
        .arg("-c")
        .arg(format!(
            "echo 'deb [signed-by=/etc/apt/keyrings/idlescreen-keyring.gpg] {REPO_BASE}/apt/ stable main' | sudo tee /etc/apt/sources.list.d/idlescreen.list >/dev/null"
        ))
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if !list_ok {
        err("Could not write /etc/apt/sources.list.d/idlescreen.list");
        exit(1);
    }
    story_line("Running apt-get update…");
    if !run_status(Command::new("sudo").args(["apt-get", "update"])) {
        err("apt-get update failed");
        exit(1);
    }
    ok("APT index updated with IdleScreen source");
}

fn print_plan(de_label: &str, cosmic: bool, pkgs: &[&str]) {
    story_line(&format!("Desktop profile → {de_label}"));
    // Honest plan: same core on every DE; COSMIC only adds idle-cosmic.
    let core = idlescreen_packages::CORE_PACKAGES.join(" ");
    println!("  {C_GREEN}→{C_RESET} Core stack (all DEs): {C_BOLD}{core}{C_RESET}");
    println!(
        "  {C_DIM}    idlescreen = product metapackage (install|remove by brand name){C_RESET}"
    );
    if cosmic {
        println!(
            "  {C_GREEN}→{C_RESET} COSMIC: also {C_BOLD}{}{C_RESET} (panel applet package)",
            idlescreen_packages::COSMIC_EXTRA
        );
    } else {
        println!("  {C_GREEN}→{C_RESET} {de_label}: no extra DE-specific packages");
    }
    println!();
    story_line("Surveying what is already on this host (installed vs channel)…");
    println!(
        "  {C_DIM}plan:{C_RESET} {C_BOLD}{}{C_RESET}",
        pkgs.join(" ")
    );
    println!();
}

fn print_survey_summary(survey: &pkg::Survey, pkgs: &[&str]) {
    println!();
    for line in
        idlescreen_packages::format_survey_summary(survey.upgrade.len(), survey.install.len())
    {
        // Color the "Survey: …" head by outcome type.
        if line.contains("outdated") {
            say(&format!("  {C_ORANGE}{C_BOLD}{line}{C_RESET}"));
        } else if line.contains("missing") {
            say(&format!("  {C_CYAN}{C_BOLD}{line}{C_RESET}"));
        } else {
            say(&format!("  {C_GREEN}{C_BOLD}{line}{C_RESET}"));
        }
    }
    println!(
        "  {C_BOLD}Will request:{C_RESET} {C_CYAN}{}{C_RESET}",
        pkgs.join(" ")
    );
}
