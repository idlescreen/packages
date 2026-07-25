//! IdleScreen installer — same product matrix and upgrade story as `install.sh`.
// SPDX-License-Identifier: Apache-2.0

use idlescreen_packages::compare_versions;
use std::cmp::Ordering;
use std::env;
use std::path::Path;
use std::process::{Command, Stdio, exit};
use std::thread::sleep;
use std::time::Duration;

const C_ORANGE: &str = "\x1b[38;5;208m";
const C_CYAN: &str = "\x1b[38;5;51m";
const C_GREEN: &str = "\x1b[38;5;82m";
const C_YELLOW: &str = "\x1b[38;5;220m";
const C_MAGENTA: &str = "\x1b[38;5;213m";
const C_DIM: &str = "\x1b[38;5;242m";
const C_BOLD: &str = "\x1b[1m";
const C_RESET: &str = "\x1b[0m";

const REPO_BASE: &str = "https://idlescreen.github.io/packages";

fn pause(ms: u64) {
    sleep(Duration::from_millis(ms));
}

fn say(line: &str) {
    println!("{line}");
}

fn story_line(msg: &str) {
    println!("  {C_MAGENTA}›{C_RESET} {C_DIM}{msg}{C_RESET}");
    pause(200);
}

fn ok(msg: &str) {
    println!(" {C_GREEN}✔{C_RESET} {msg}");
}

fn warn(msg: &str) {
    println!(" {C_YELLOW}!{C_RESET} {msg}");
}

fn err(msg: &str) {
    eprintln!(" {C_YELLOW}ERROR:{C_RESET} {msg}");
}

fn step(msg: &str) {
    println!();
    println!(" {C_CYAN}{C_BOLD}{msg}{C_RESET}");
}

fn which(bin: &str) -> bool {
    Command::new("sh")
        .args(["-c", &format!("command -v {bin} >/dev/null 2>&1")])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn run_status(cmd: &mut Command) -> bool {
    cmd.status().map(|s| s.success()).unwrap_or(false)
}

fn run_capture(cmd: &mut Command) -> Option<String> {
    let out = cmd
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if s.is_empty() { None } else { Some(s) }
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
    ("other", "Generic / unknown DE")
}

fn packages(cosmic: bool) -> Vec<&'static str> {
    // Modular stack + product metapackage (dnf/apt install|remove idlescreen).
    let mut p = vec![
        "idle-daemon",
        "idle-cli",
        "idle-savers",
        "idle-tui",
        "idlescreen",
    ];
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

fn version_is_older(installed: &str, candidate: &str) -> bool {
    !installed.is_empty()
        && !candidate.is_empty()
        && compare_versions(installed, candidate) == Ordering::Less
}

fn rpm_installed(pkg: &str) -> Option<String> {
    run_capture(Command::new("rpm").args(["-q", "--qf", "%{VERSION}-%{RELEASE}", pkg]))
}

fn rpm_available(pkg: &str) -> Option<String> {
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

fn apt_installed(pkg: &str) -> Option<String> {
    run_capture(Command::new("dpkg-query").args(["-W", "-f=${Version}", pkg]))
}

fn apt_candidate(pkg: &str) -> Option<String> {
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

#[derive(Default)]
struct Survey {
    upgrade: Vec<String>,
    install: Vec<String>,
    current: Vec<String>,
}

fn survey(pkgs: &[&str], dnf: bool) -> Survey {
    let mut s = Survey::default();
    for pkg in pkgs {
        let (inst, cand) = if dnf {
            (rpm_installed(pkg), rpm_available(pkg))
        } else {
            (apt_installed(pkg), apt_candidate(pkg))
        };

        match (inst.as_deref(), cand.as_deref()) {
            (None, _) => {
                println!(
                    "  {C_ORANGE}○{C_RESET} {C_BOLD}{pkg}{C_RESET}  {C_DIM}not installed{C_RESET}  →  {C_CYAN}install{C_RESET}"
                );
                s.install.push((*pkg).to_string());
            }
            (Some(i), Some(c)) if version_is_older(i, c) => {
                println!(
                    "  {C_YELLOW}↑{C_RESET} {C_BOLD}{pkg}{C_RESET}  {C_DIM}{i}{C_RESET}  →  {C_GREEN}{c}{C_RESET}  {C_ORANGE}upgrade{C_RESET}"
                );
                s.upgrade.push((*pkg).to_string());
            }
            (Some(i), Some(c)) => {
                println!(
                    "  {C_GREEN}✔{C_RESET} {C_BOLD}{pkg}{C_RESET}  {C_DIM}{i}{C_RESET}  {C_GREEN}current{C_RESET} {C_DIM}(={c}){C_RESET}"
                );
                s.current.push((*pkg).to_string());
            }
            (Some(i), None) => {
                println!(
                    "  {C_GREEN}✔{C_RESET} {C_BOLD}{pkg}{C_RESET}  {C_DIM}{i}{C_RESET}  {C_DIM}(no channel version yet){C_RESET}"
                );
                s.current.push((*pkg).to_string());
            }
        }
    }
    s
}

fn dnf_upgrade(pkgs: &[String]) -> bool {
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

fn dnf_install(pkgs: &[String]) -> bool {
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

fn apt_only_upgrade(pkgs: &[String]) -> bool {
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

fn apt_install(pkgs: &[String]) -> bool {
    if pkgs.is_empty() {
        return true;
    }
    let mut cmd = Command::new("sudo");
    cmd.arg("apt-get").arg("install").arg("-y").args(pkgs);
    run_status(&mut cmd)
}

fn main() {
    let arch = env::consts::ARCH;
    let session = env::var("XDG_SESSION_TYPE").unwrap_or_else(|_| "unknown".into());
    let (de_id, de_label) = desktop_label();
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
    println!("  {C_DIM}desktop{C_RESET}  {C_GREEN}{de_label}{C_RESET} {C_DIM}({de_id}){C_RESET}");

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
    if dnf {
        story_line("Fetching signed repository manifest…");
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
        story_line("Refreshing IdleScreen channel metadata (so older builds are not left behind)…");
        let _ = run_status(
            Command::new("sudo")
                .args(["dnf", "clean", "metadata", "--repo=idlescreen"])
                .stdout(Stdio::null())
                .stderr(Stdio::null()),
        );
        if !run_status(
            Command::new("sudo")
                .args(["dnf", "makecache", "--refresh", "--repo=idlescreen"])
                .stdout(Stdio::null())
                .stderr(Stdio::null()),
        ) {
            let _ = run_status(
                Command::new("sudo")
                    .args(["dnf", "makecache", "--refresh"])
                    .stdout(Stdio::null())
                    .stderr(Stdio::null()),
            );
        }
        ok("DNF channel metadata current");
    } else {
        story_line("Provisioning keyring vault…");
        let _ = run_status(Command::new("sudo").args(["mkdir", "-p", "/etc/apt/keyrings"]));
        story_line("Importing IdleScreen signing key…");
        let _ = Command::new("sh")
            .arg("-c")
            .arg(format!(
                "curl -fsSL {REPO_BASE}/apt/idlescreen-keyring.gpg | sudo tee /etc/apt/keyrings/idlescreen-keyring.gpg >/dev/null"
            ))
            .status();
        story_line("Registering stable/main channel…");
        let _ = Command::new("sh")
            .arg("-c")
            .arg(format!(
                "echo 'deb [signed-by=/etc/apt/keyrings/idlescreen-keyring.gpg] {REPO_BASE}/apt/ stable main' | sudo tee /etc/apt/sources.list.d/idlescreen.list >/dev/null"
            ))
            .status();
        story_line("Refreshing package index…");
        if !run_status(Command::new("sudo").args(["apt-get", "update"])) {
            err("apt-get update failed");
            exit(1);
        }
        ok("APT channel ready");
    }

    step("[3/5]  Composing the install plan");
    story_line(&format!("Matching desktop profile → {de_label}"));
    match de_id {
        "cosmic" => say(&format!(
            "  {C_GREEN}→{C_RESET} COSMIC detected — including {C_BOLD}idle-cosmic{C_RESET} panel applet"
        )),
        "hyprland" | "sway" | "gnome" | "kde" => say(&format!(
            "  {C_GREEN}→{C_RESET} {de_label} detected — daemon + TUI + full saver set"
        )),
        _ => say(&format!(
            "  {C_GREEN}→{C_RESET} Generic / other DE — core package set"
        )),
    }
    println!("  {C_GREEN}→{C_RESET} Always:     idle-daemon  idle-cli  idle-savers  idle-tui");
    if cosmic {
        println!("  {C_GREEN}→{C_RESET} Plus:       idle-cosmic");
    }
    println!();
    story_line("Surveying what is already on this host…");
    println!(
        "  {C_DIM}manifest:{C_RESET} {C_BOLD}{}{C_RESET}",
        pkgs.join(" ")
    );
    println!();

    let survey = survey(&pkgs, dnf);
    println!();
    if !survey.upgrade.is_empty() {
        say(&format!(
            "  {C_ORANGE}{C_BOLD}Found {} outdated IdleScreen module(s){C_RESET} — will raise to channel.",
            survey.upgrade.len()
        ));
    }
    if !survey.install.is_empty() {
        say(&format!(
            "  {C_CYAN}{C_BOLD}Found {} missing module(s){C_RESET} — will install.",
            survey.install.len()
        ));
    }
    if survey.upgrade.is_empty() && survey.install.is_empty() {
        say(&format!(
            "  {C_GREEN}{C_BOLD}All planned modules already current{C_RESET} — will still re-sync with the channel."
        ));
    }
    println!(
        "  {C_BOLD}Will ensure:{C_RESET} {C_CYAN}{}{C_RESET}",
        pkgs.join(" ")
    );
    pause(400);

    step("[4/5]  Deploying modules into the system");
    let all: Vec<String> = pkgs.iter().map(|s| (*s).to_string()).collect();

    if dnf {
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
        if !dnf_upgrade(&all) {
            warn("dnf upgrade (full set) soft-failed — trying install…");
        }
        if !dnf_install(&all) {
            err(&format!("dnf install failed for: {}", all.join(" ")));
            exit(1);
        }
        story_line("Verifying RPM database…");
        if rpm_installed("idle-daemon").is_none() || rpm_installed("idle-cli").is_none() {
            err("idle-daemon / idle-cli missing after install");
            exit(1);
        }
        println!();
        for p in &pkgs {
            if let Some(v) = run_capture(Command::new("rpm").args(["-q", p])) {
                ok(&v);
            } else {
                warn(&format!("{p} not present after deploy"));
            }
        }
    } else {
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
        if !apt_install(&all) {
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
        for p in &pkgs {
            if let Some(v) =
                run_capture(Command::new("dpkg-query").args(["-W", "-f=${Package} ${Version}", p]))
            {
                ok(&v);
            } else {
                warn(&format!("{p} not present after deploy"));
            }
        }
    }
    println!();
    if !survey.upgrade.is_empty() {
        ok(&format!(
            "{C_BOLD}Payload secured — outdated modules raised.{C_RESET}"
        ));
    } else {
        ok(&format!("{C_BOLD}Payload secured.{C_RESET}"));
    }

    step("[5/5]  Awakening the idle daemon");
    story_line("Creating user config directories…");
    if let Ok(home) = env::var("HOME") {
        let _ = std::fs::create_dir_all(format!("{home}/.config/idle"));
    }
    story_line("Reloading user systemd units…");
    let _ = run_status(Command::new("systemctl").args(["--user", "daemon-reload"]));
    story_line("Enabling idle-daemon.service…");
    let _ = run_status(Command::new("systemctl").args([
        "--user",
        "enable",
        "--now",
        "idle-daemon.service",
    ]));
    let active =
        run_capture(Command::new("systemctl").args(["--user", "is-active", "idle-daemon.service"]))
            .map(|s| s == "active")
            .unwrap_or(false);
    if active {
        ok(&format!(
            "Daemon {C_GREEN}{C_BOLD}active{C_RESET}  ·  idle-daemon.service"
        ));
    } else {
        warn("Daemon unit configured — start later with:");
        println!("    systemctl --user enable --now idle-daemon.service");
    }

    println!();
    println!("  {C_GREEN}{C_BOLD}");
    println!("        ╔══════════════════════════════════════════════════════╗");
    println!("        ║                                                      ║");
    println!("        ║             ✦  INSTALLATION COMPLETE  ✦              ║");
    println!("        ║                                                      ║");
    println!("        ╚══════════════════════════════════════════════════════╝");
    println!("  {C_RESET}");
    println!("  {C_DIM}host{C_RESET}     {os_name}  ({arch})");
    println!("  {C_DIM}desktop{C_RESET}  {de_label}");
    println!("  {C_DIM}channel{C_RESET}  {channel}");
    println!("  {C_DIM}modules{C_RESET}  {}", pkgs.join(" "));
    if !survey.upgrade.is_empty() {
        println!(
            "  {C_DIM}raised{C_RESET}   {C_GREEN}{}{C_RESET} outdated module(s) upgraded to channel",
            survey.upgrade.len()
        );
    }
    if !survey.install.is_empty() {
        println!(
            "  {C_DIM}seated{C_RESET}   {C_CYAN}{}{C_RESET} new module(s) installed",
            survey.install.len()
        );
    }
    if cosmic {
        println!("  {C_ORANGE}COSMIC{C_RESET} applet package idle-cosmic included");
    }
    println!();
    println!("  {C_BOLD}Quick start{C_RESET}");
    println!("    {C_CYAN}idlescreen tui{C_RESET}        interactive dashboard");
    println!("    {C_CYAN}idlescreen status{C_RESET}     daemon + saver state");
    println!("    {C_CYAN}idlescreen preview beams{C_RESET}  try an effect");
    println!("    {C_CYAN}idlescreen doctor{C_RESET}     system diagnostics");
    println!();
    println!("  {C_DIM}docs  {C_RESET}https://idlescreen.github.io");
    println!("  {C_DIM}pkgs  {C_RESET}{REPO_BASE}/");
    println!("  {C_DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{C_RESET}");
    println!();
}
