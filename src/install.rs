//! IdleScreen installer — same product matrix as `install.sh`.
//! Never installs `idle-studio` (separate product).
// SPDX-License-Identifier: Apache-2.0

use std::env;
use std::path::Path;
use std::process::{Command, exit};
use std::thread::sleep;
use std::time::Duration;

const C_ORANGE: &str = "\x1b[38;5;208m";
const C_CYAN: &str = "\x1b[38;5;51m";
const C_GREEN: &str = "\x1b[38;5;82m";
const C_YELLOW: &str = "\x1b[38;5;220m";
const C_DIM: &str = "\x1b[38;5;242m";
const C_BOLD: &str = "\x1b[1m";
const C_RESET: &str = "\x1b[0m";

fn pause(ms: u64) {
    sleep(Duration::from_millis(ms));
}

fn ok_cmd(cmd: &mut Command, what: &str) -> bool {
    match cmd.status() {
        Ok(st) if st.success() => true,
        _ => {
            eprintln!("{C_YELLOW}ERROR:{C_RESET} {what} failed");
            false
        }
    }
}

fn which(bin: &str) -> bool {
    Command::new("sh")
        .args(["-c", &format!("command -v {bin} >/dev/null 2>&1")])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn is_dnf() -> bool {
    Path::new("/usr/bin/dnf").exists() || which("dnf")
}

fn is_apt() -> bool {
    Path::new("/usr/bin/apt-get").exists() || which("apt-get")
}

fn is_cosmic() -> bool {
    let de = env::var("XDG_CURRENT_DESKTOP")
        .or_else(|_| env::var("XDG_SESSION_DESKTOP"))
        .unwrap_or_default()
        .to_ascii_lowercase();
    Path::new("/usr/bin/cosmic-panel").exists()
        || Path::new("/usr/bin/cosmic-comp").exists()
        || de.contains("cosmic")
}

fn desktop_label() -> (&'static str, &'static str) {
    let de = env::var("XDG_CURRENT_DESKTOP")
        .or_else(|_| env::var("XDG_SESSION_DESKTOP"))
        .or_else(|_| env::var("DESKTOP_SESSION"))
        .unwrap_or_default()
        .to_ascii_lowercase();
    if is_cosmic() {
        return ("cosmic", "COSMIC Desktop");
    }
    if env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some() || de.contains("hyprland") {
        return ("hyprland", "Hyprland");
    }
    if env::var_os("SWAYSOCK").is_some() || de.contains("sway") {
        return ("sway", "Sway");
    }
    if de.contains("gnome") {
        return ("gnome", "GNOME");
    }
    if de.contains("kde") || de.contains("plasma") {
        return ("kde", "KDE Plasma");
    }
    if de.contains("xfce") {
        return ("xfce", "Xfce");
    }
    ("other", "Generic Wayland / unknown DE")
}

/// Core product set. Never includes idle-studio.
fn packages(cosmic: bool) -> Vec<&'static str> {
    let mut p = vec!["idle-daemon", "idle-cli", "idle-savers", "idle-tui"];
    if cosmic {
        p.push("idle-cosmic");
    }
    p
}

fn os_pretty() -> String {
    if let Ok(text) = std::fs::read_to_string("/etc/os-release") {
        for line in text.lines() {
            if let Some(rest) = line.strip_prefix("PRETTY_NAME=") {
                return rest.trim().trim_matches('"').to_string();
            }
        }
    }
    "Unknown Linux".into()
}

fn main() {
    let arch = env::consts::ARCH;
    let session = env::var("XDG_SESSION_TYPE").unwrap_or_else(|_| "unknown".into());
    let (de_id, de_label) = desktop_label();
    let cosmic = is_cosmic();
    let pkgs = packages(cosmic);
    let os_name = os_pretty();

    println!("\n{C_ORANGE}{C_BOLD}IdleScreen installer{C_RESET}");
    println!("{C_DIM}  Ambient screensavers for Wayland · not studio{C_RESET}");
    println!("{C_DIM}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{C_RESET}");
    pause(150);

    println!("\n {C_CYAN}{C_BOLD}[1/5]{C_RESET} {C_BOLD}Scanning host identity{C_RESET}");
    println!("  {C_DIM}os{C_RESET}       {C_GREEN}{os_name}{C_RESET}");
    println!("  {C_DIM}arch{C_RESET}     {C_GREEN}{arch}{C_RESET}");
    println!("  {C_DIM}session{C_RESET}  {C_GREEN}{session}{C_RESET}");
    println!("  {C_DIM}desktop{C_RESET}  {C_GREEN}{de_label}{C_RESET} {C_DIM}({de_id}){C_RESET}");

    let dnf = is_dnf();
    let apt = is_apt();
    if !dnf && !apt {
        eprintln!("{C_YELLOW}ERROR:{C_RESET} need DNF or APT — https://idlescreen.github.io/packages/");
        exit(1);
    }
    println!(
        "  {C_DIM}packages{C_RESET} {C_GREEN}{}{C_RESET}",
        if dnf { "DNF · RPM host" } else { "APT · Debian family" }
    );
    pause(200);

    println!("\n {C_CYAN}{C_BOLD}[2/5]{C_RESET} {C_BOLD}Opening the package gate{C_RESET}");
    if dnf {
        if !ok_cmd(
            Command::new("sudo").args([
                "curl",
                "-fsSL",
                "https://idlescreen.github.io/packages/rpm/idlescreen.repo",
                "-o",
                "/etc/yum.repos.d/idlescreen.repo",
            ]),
            "repo install",
        ) {
            exit(1);
        }
        println!("  {C_GREEN}✔{C_RESET} /etc/yum.repos.d/idlescreen.repo");
    } else {
        let _ = Command::new("sudo")
            .args(["mkdir", "-p", "/etc/apt/keyrings"])
            .status();
        let _ = Command::new("sh").arg("-c").arg(
            "curl -fsSL https://idlescreen.github.io/packages/idlescreen-keyring.gpg | sudo tee /etc/apt/keyrings/idlescreen-keyring.gpg >/dev/null",
        ).status();
        let _ = Command::new("sh").arg("-c").arg(
            "echo 'deb [signed-by=/etc/apt/keyrings/idlescreen-keyring.gpg] https://idlescreen.github.io/packages/apt/ stable main' | sudo tee /etc/apt/sources.list.d/idlescreen.list >/dev/null",
        ).status();
        if !ok_cmd(
            Command::new("sudo").args(["apt-get", "update"]),
            "apt-get update",
        ) {
            exit(1);
        }
        println!("  {C_GREEN}✔{C_RESET} APT channel ready");
    }

    println!("\n {C_CYAN}{C_BOLD}[3/5]{C_RESET} {C_BOLD}Composing the install plan{C_RESET}");
    println!("  {C_GREEN}→{C_RESET} {de_label}");
    println!("  {C_GREEN}→{C_RESET} {C_CYAN}{}{C_RESET}", pkgs.join(" "));
    println!("  {C_DIM}→ skip: idle-studio (separate product){C_RESET}");
    for n in (1..=3).rev() {
        println!("  {C_ORANGE}deploy in {n}…{C_RESET}");
        pause(350);
    }

    println!("\n {C_CYAN}{C_BOLD}[4/5]{C_RESET} {C_BOLD}Deploying modules{C_RESET}");
    if dnf {
        let mut cmd = Command::new("sudo");
        cmd.arg("dnf").arg("install").arg("-y").args(&pkgs);
        if !ok_cmd(&mut cmd, "dnf install") {
            exit(1);
        }
        if !ok_cmd(
            Command::new("rpm").args(["-q", "idle-daemon", "idle-cli"]),
            "rpm verify",
        ) {
            exit(1);
        }
    } else {
        let mut cmd = Command::new("sudo");
        cmd.arg("apt-get").arg("install").arg("-y").args(&pkgs);
        if !ok_cmd(&mut cmd, "apt-get install") {
            let retry: Vec<&str> = pkgs.iter().copied().filter(|p| *p != "idle-tui").collect();
            let mut cmd2 = Command::new("sudo");
            cmd2.arg("apt-get").arg("install").arg("-y").args(&retry);
            if !ok_cmd(&mut cmd2, "apt-get install (retry)") {
                exit(1);
            }
        }
        if !ok_cmd(
            Command::new("dpkg-query").args(["-W", "idle-daemon", "idle-cli"]),
            "dpkg verify",
        ) {
            exit(1);
        }
    }

    println!("\n {C_CYAN}{C_BOLD}[5/5]{C_RESET} {C_BOLD}Awakening the idle daemon{C_RESET}");
    if let Ok(home) = env::var("HOME") {
        let _ = std::fs::create_dir_all(format!("{home}/.config/idle"));
        let _ = std::fs::create_dir_all(format!("{home}/.config/idlescreen"));
    }
    let _ = Command::new("systemctl")
        .args(["--user", "daemon-reload"])
        .status();
    let _ = Command::new("systemctl")
        .args(["--user", "enable", "--now", "idle-daemon.service"])
        .status();
    let active = Command::new("systemctl")
        .args(["--user", "is-active", "idle-daemon.service"])
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim() == "active")
        .unwrap_or(false);
    if active {
        println!("  {C_GREEN}✔{C_RESET} daemon active · idle-daemon.service");
    } else {
        println!("  {C_YELLOW}!{C_RESET} unit configured — systemctl --user enable --now idle-daemon.service");
    }

    println!("\n {C_GREEN}{C_BOLD}✦ INSTALLATION COMPLETE ✦{C_RESET}");
    println!("  modules: {C_CYAN}{}{C_RESET}", pkgs.join(" "));
    println!("  studio:  {C_DIM}not installed (separate product){C_RESET}");
    if cosmic {
        println!("  {C_ORANGE}COSMIC{C_RESET} applet package idle-cosmic included");
    }
    println!("\n {C_BOLD}Quick start{C_RESET}");
    println!("   {C_CYAN}idlescreen tui{C_RESET}");
    println!("   {C_CYAN}idlescreen status{C_RESET}");
    println!("   {C_CYAN}idlescreen doctor{C_RESET}");
    println!();
}
