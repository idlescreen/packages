// SPDX-License-Identifier: Apache-2.0

//! Deploy packages and start the user service.

use std::env;
use std::process::{Command, exit};

use super::host::{run_capture, run_status};
use super::pkg::{
    apt_install, apt_installed, apt_only_upgrade, dnf_install, dnf_upgrade, pkg_present,
    rpm_installed, Survey,
};
use super::ui::{C_BOLD, C_GREEN, C_RESET, err, ok, story_line, warn};

pub fn deploy(dnf: bool, pkgs: &[&str], survey: &Survey) {
    let all: Vec<String> = pkgs.iter().map(|s| (*s).to_string()).collect();
    if dnf {
        deploy_dnf(&all, survey, pkgs);
    } else {
        deploy_apt(&all, survey, pkgs);
    }
}

fn deploy_dnf(all: &[String], survey: &Survey, pkgs: &[&str]) {
    if !survey.upgrade.is_empty() {
        story_line("Raising outdated IdleScreen modules to the current channel…");
        if !dnf_upgrade(&survey.upgrade) {
            warn("dnf upgrade reported issues — continuing with install re-sync…");
        }
    }
    if !survey.install.is_empty() {
        story_line("Seating new IdleScreen modules…");
        if !dnf_install(&survey.install) {
            err(&format!(
                "dnf install failed for: {}",
                survey.install.join(" ")
            ));
            exit(1);
        }
    }
    story_line("Re-syncing the full IdleScreen set against the channel…");
    if !dnf_upgrade(all) {
        warn("dnf upgrade (full set) soft-failed — trying install…");
    }
    if !dnf_install(all) {
        err(&format!("dnf install failed for: {}", all.join(" ")));
        exit(1);
    }
    story_line("Verifying RPM database…");
    if rpm_installed("idle-daemon").is_none() || rpm_installed("idle-cli").is_none() {
        err("idle-daemon / idle-cli missing after install");
        exit(1);
    }
    println!();
    for p in pkgs {
        if let Some(v) = run_capture(Command::new("rpm").args(["-q", p])) {
            ok(&v);
        } else {
            warn(&format!("{p} not present after deploy"));
        }
    }
}

fn deploy_apt(all: &[String], survey: &Survey, pkgs: &[&str]) {
    if !survey.upgrade.is_empty() {
        story_line("Raising outdated IdleScreen modules to the current channel…");
        if !apt_only_upgrade(&survey.upgrade) {
            warn("apt only-upgrade soft-failed — continuing with full install…");
        }
    }
    if !survey.install.is_empty() {
        story_line("Seating new IdleScreen modules…");
        let _ = apt_install(&survey.install);
    }
    story_line("Re-syncing the full IdleScreen set against the channel…");
    if !apt_install(all) {
        warn("Full set failed — retrying without idle-tui…");
        let retry: Vec<String> = all
            .iter()
            .filter(|p| p.as_str() != "idle-tui")
            .cloned()
            .collect();
        if !apt_install(&retry) {
            err("apt-get install failed");
            exit(1);
        }
    }
    story_line("Verifying dpkg database…");
    if apt_installed("idle-daemon").is_none() || apt_installed("idle-cli").is_none() {
        err("idle-daemon / idle-cli missing after install");
        exit(1);
    }
    println!();
    for p in pkgs {
        if let Some(v) =
            run_capture(Command::new("dpkg-query").args(["-W", "-f=${Package} ${Version}", p]))
        {
            ok(&v);
        } else {
            warn(&format!("{p} not present after deploy"));
        }
    }
}

pub fn recount<'a>(pkgs: &[&'a str], dnf: bool) -> (Vec<&'a str>, Vec<&'a str>) {
    let present: Vec<&str> = pkgs
        .iter()
        .copied()
        .filter(|p| pkg_present(p, dnf))
        .collect();
    let missing: Vec<&str> = pkgs
        .iter()
        .copied()
        .filter(|p| !pkg_present(p, dnf))
        .collect();
    (present, missing)
}

pub fn print_deploy_result(present: &[&str], missing: &[&str], planned: usize) {
    println!();
    if missing.is_empty() {
        ok(&format!(
            "{C_BOLD}Deploy finished — all {} planned package(s) present.{C_RESET}",
            present.len()
        ));
    } else {
        warn(&format!(
            "Deploy finished — {}/{planned} planned package(s) present.",
            present.len()
        ));
        warn(&format!("Missing: {}", missing.join(" ")));
    }
}

pub fn start_daemon() -> bool {
    story_line("Ensuring ~/.config/idle exists (daemon config dir)…");
    if let Ok(home) = env::var("HOME") {
        let _ = std::fs::create_dir_all(format!("{home}/.config/idle"));
    }
    story_line("Reloading user systemd units…");
    let _ = run_status(Command::new("systemctl").args(["--user", "daemon-reload"]));
    story_line("systemctl --user enable --now idle-daemon.service…");
    if !run_status(Command::new("systemctl").args([
        "--user",
        "enable",
        "--now",
        "idle-daemon.service",
    ])) {
        warn("enable --now returned non-zero (may need a graphical user session)");
    }
    let active =
        run_capture(Command::new("systemctl").args(["--user", "is-active", "idle-daemon.service"]))
            .map(|s| s == "active")
            .unwrap_or(false);
    if active {
        ok(&format!(
            "idle-daemon.service is {C_GREEN}{C_BOLD}active{C_RESET} (user session)"
        ));
    } else {
        warn("idle-daemon.service is not active right now.");
        println!("    Packages may still be installed. Start later with:");
        println!("    systemctl --user enable --now idle-daemon.service");
        println!("    (requires a logged-in user session with systemd --user)");
    }
    active
}
