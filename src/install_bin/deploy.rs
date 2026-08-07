// SPDX-License-Identifier: Apache-2.0

//! Deploy packages and start the user service.

use std::env;
use std::process::{Command, exit};

use super::host::{run_capture, run_status};
use super::pkg::{
    Survey, apt_install, apt_installed, apt_only_upgrade, dnf_install, dnf_upgrade, pkg_present,
    rpm_installed,
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
    let line = idlescreen_packages::format_deploy_result(present.len(), planned);
    if missing.is_empty() {
        ok(&format!("{C_BOLD}{line}{C_RESET}"));
    } else {
        warn(&line);
        warn(&format!("Missing: {}", missing.join(" ")));
    }
}

pub fn start_daemon() -> bool {
    story_line("Ensuring ~/.config/idle exists (daemon config dir)…");
    if let Ok(home) = env::var("HOME") {
        let _ = std::fs::create_dir_all(format!("{home}/.config/idle"));
        let _ = std::fs::create_dir_all(format!("{home}/.config/idlescreen"));
    }
    story_line("Reloading user systemd units…");
    let _ = run_status(Command::new("systemctl").args(["--user", "daemon-reload"]));
    let _ = run_status(Command::new("systemctl").args([
        "--user",
        "reset-failed",
        "idle-daemon.service",
    ]));
    story_line("systemctl --user enable idle-daemon.service…");
    let _ = run_status(Command::new("systemctl").args(["--user", "enable", "idle-daemon.service"]));
    story_line("systemctl --user start idle-daemon.service…");
    if !run_status(Command::new("systemctl").args(["--user", "start", "idle-daemon.service"])) {
        warn("start returned non-zero — retrying once…");
        std::thread::sleep(std::time::Duration::from_millis(500));
        let _ = run_status(Command::new("systemctl").args([
            "--user",
            "reset-failed",
            "idle-daemon.service",
        ]));
        let _ =
            run_status(Command::new("systemctl").args(["--user", "start", "idle-daemon.service"]));
    }
    // Brief wait for Type=dbus to claim the bus name.
    for _ in 0..25 {
        let active = run_capture(Command::new("systemctl").args([
            "--user",
            "is-active",
            "idle-daemon.service",
        ]))
        .map(|s| s == "active")
        .unwrap_or(false);
        if active {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(200));
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
        // Last-resort direct spawn (unit file race / session quirks).
        warn("user unit not active — trying direct idle-daemon spawn…");
        let _ = Command::new("idle-daemon").arg("daemon").spawn();
        std::thread::sleep(std::time::Duration::from_millis(600));
        let active2 = run_capture(Command::new("systemctl").args([
            "--user",
            "is-active",
            "idle-daemon.service",
        ]))
        .map(|s| s == "active")
        .unwrap_or(false);
        if active2 {
            ok(&format!(
                "idle-daemon is up ({C_GREEN}{C_BOLD}bus/service{C_RESET})"
            ));
            return true;
        }
        warn("idle-daemon.service is not active right now.");
        println!("    Packages may still be installed. Start later with:");
        println!("    systemctl --user enable --now idle-daemon.service");
        println!("    or: idlescreen doctor --fix");
        println!("    (requires a logged-in user session with systemd --user)");
    }
    active
}
