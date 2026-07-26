// SPDX-License-Identifier: Apache-2.0

//! Host identity: package manager, desktop, OS label.

use std::env;
use std::path::Path;
use std::process::{Command, Stdio};

pub fn which(bin: &str) -> bool {
    Command::new("sh")
        .args(["-c", &format!("command -v {bin} >/dev/null 2>&1")])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

pub fn run_status(cmd: &mut Command) -> bool {
    cmd.status().map(|s| s.success()).unwrap_or(false)
}

pub fn run_capture(cmd: &mut Command) -> Option<String> {
    let out = cmd
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if s.is_empty() {
        None
    } else {
        Some(s)
    }
}

pub fn is_dnf() -> bool {
    Path::new("/usr/bin/dnf").exists() || which("dnf")
}

pub fn is_apt() -> bool {
    Path::new("/usr/bin/apt-get").exists() || which("apt-get")
}

pub fn is_cosmic() -> bool {
    let de = env::var("XDG_CURRENT_DESKTOP")
        .or_else(|_| env::var("XDG_SESSION_DESKTOP"))
        .unwrap_or_default()
        .to_ascii_lowercase();
    Path::new("/usr/bin/cosmic-panel").exists()
        || Path::new("/usr/bin/cosmic-comp").exists()
        || de.contains("cosmic")
}

pub fn desktop_label() -> (&'static str, &'static str) {
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

/// Same core on every DE; COSMIC only adds idle-cosmic.
pub fn packages(cosmic: bool) -> Vec<&'static str> {
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

pub fn os_pretty() -> String {
    if let Ok(text) = std::fs::read_to_string("/etc/os-release") {
        for line in text.lines() {
            if let Some(rest) = line.strip_prefix("PRETTY_NAME=") {
                return rest.trim().trim_matches('"').to_string();
            }
        }
    }
    "Unknown Linux".into()
}
