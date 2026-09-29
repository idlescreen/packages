// SPDX-License-Identifier: Apache-2.0

//! Package survey + dnf/apt install helpers.

use idlescreen_packages::{SurveyClass, classify_package};
use std::process::Command;

use super::host::{run_capture, run_status};
use super::ui::{C_BOLD, C_CYAN, C_DIM, C_GREEN, C_ORANGE, C_RESET, C_YELLOW};

pub fn rpm_installed(pkg: &str) -> Option<String> {
    run_capture(Command::new("rpm").args(["-q", "--qf", "%{VERSION}-%{RELEASE}", pkg]))
}

pub fn rpm_available(pkg: &str) -> Option<String> {
    run_capture(Command::new("dnf").args([
        "-q",
        "repoquery",
        "--repo=idlescreen",
        "--latest-limit=1",
        "--qf",
        "%{version}-%{release}",
        pkg,
    ]))
    .or_else(|| {
        run_capture(Command::new("dnf").args([
            "-q",
            "repoquery",
            "--latest-limit=1",
            "--qf",
            "%{version}-%{release}",
            pkg,
        ]))
    })
}

pub fn apt_installed(pkg: &str) -> Option<String> {
    run_capture(Command::new("dpkg-query").args(["-W", "-f=${Version}", pkg]))
}

pub fn apt_candidate(pkg: &str) -> Option<String> {
    let out = run_capture(Command::new("apt-cache").args(["policy", pkg]))?;
    for line in out.lines() {
        let t = line.trim();
        if let Some(rest) = t.strip_prefix("Candidate:") {
            let v = rest.trim();
            if v.is_empty() || v == "(none)" {
                return None;
            }
            return Some(v.to_string());
        }
    }
    None
}

pub fn pkg_present(pkg: &str, dnf: bool) -> bool {
    if dnf {
        rpm_installed(pkg).is_some()
    } else {
        apt_installed(pkg).is_some()
    }
}

#[derive(Default)]
pub struct Survey {
    pub upgrade: Vec<String>,
    pub install: Vec<String>,
    pub current: Vec<String>,
}

pub fn survey(pkgs: &[&str], dnf: bool) -> Survey {
    let mut s = Survey::default();
    for pkg in pkgs {
        let (inst, cand) = if dnf {
            (rpm_installed(pkg), rpm_available(pkg))
        } else {
            (apt_installed(pkg), apt_candidate(pkg))
        };

        match classify_package(inst.as_deref(), cand.as_deref()) {
            SurveyClass::Install => {
                println!(
                    "  {C_ORANGE}○{C_RESET} {C_BOLD}{pkg}{C_RESET}  {C_DIM}not installed{C_RESET}  →  {C_CYAN}install{C_RESET}"
                );
                s.install.push((*pkg).to_string());
            }
            SurveyClass::Upgrade => {
                let i = inst.as_deref().unwrap_or("?");
                let c = cand.as_deref().unwrap_or("?");
                println!(
                    "  {C_YELLOW}↑{C_RESET} {C_BOLD}{pkg}{C_RESET}  {C_DIM}{i}{C_RESET}  →  {C_GREEN}{c}{C_RESET}  {C_ORANGE}upgrade{C_RESET}"
                );
                s.upgrade.push((*pkg).to_string());
            }
            SurveyClass::Current => {
                let i = inst.as_deref().unwrap_or("?");
                let c = cand.as_deref().unwrap_or("?");
                println!(
                    "  {C_GREEN}✔{C_RESET} {C_BOLD}{pkg}{C_RESET}  {C_DIM}{i}{C_RESET}  {C_GREEN}matches channel{C_RESET} {C_DIM}(={c}){C_RESET}"
                );
                s.current.push((*pkg).to_string());
            }
            SurveyClass::CurrentUnknown => {
                let i = inst.as_deref().unwrap_or("?");
                println!(
                    "  {C_GREEN}✔{C_RESET} {C_BOLD}{pkg}{C_RESET}  {C_DIM}{i}{C_RESET}  {C_DIM}(installed; channel version unknown){C_RESET}"
                );
                s.current.push((*pkg).to_string());
            }
        }
    }
    s
}

pub fn dnf_upgrade(pkgs: &[String]) -> bool {
    if pkgs.is_empty() {
        return true;
    }
    let mut cmd = Command::new("sudo");
    cmd.arg("dnf")
        .arg("upgrade")
        .arg("-y")
        .arg("--refresh")
        .args(pkgs);
    run_status(&mut cmd)
}

pub fn dnf_install(pkgs: &[String]) -> bool {
    if pkgs.is_empty() {
        return true;
    }
    let mut cmd = Command::new("sudo");
    cmd.arg("dnf")
        .arg("install")
        .arg("-y")
        .arg("--refresh")
        .args(pkgs);
    run_status(&mut cmd)
}

pub fn apt_only_upgrade(pkgs: &[String]) -> bool {
    if pkgs.is_empty() {
        return true;
    }
    let mut cmd = Command::new("sudo");
    cmd.arg("apt-get")
        .arg("install")
        .arg("-y")
        .arg("--only-upgrade")
        .args(pkgs);
    run_status(&mut cmd)
}

pub fn apt_install(pkgs: &[String]) -> bool {
    if pkgs.is_empty() {
        return true;
    }
    let mut cmd = Command::new("sudo");
    cmd.arg("apt-get").arg("install").arg("-y").args(pkgs);
    run_status(&mut cmd)
}
