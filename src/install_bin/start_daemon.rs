// SPDX-License-Identifier: Apache-2.0

//! Post-deploy: enable/start idle-daemon and claim the session bus name.

use std::env;
use std::process::Command;

use super::host::{run_capture, run_status};
use super::ui::{C_BOLD, C_GREEN, C_RESET, ok, story_line, warn};

fn unit_active() -> bool {
    run_capture(Command::new("systemctl").args(["--user", "is-active", "idle-daemon.service"]))
        .map(|s| s == "active")
        .unwrap_or(false)
}

fn bus_name_up() -> bool {
    run_status(
        Command::new("busctl")
            .args(["--user", "--timeout=1", "status", "io.github.idlescreen.Idle"]),
    )
}

fn daemon_ready() -> bool {
    unit_active() && bus_name_up()
}

/// Older RPMs shipped `User=session` which dbus-broker rejects.
fn fix_dbus_activation_file() {
    let path = "/usr/share/dbus-1/services/io.github.idlescreen.Idle.service";
    let Ok(text) = std::fs::read_to_string(path) else {
        return;
    };
    if !text.lines().any(|l| l.trim() == "User=session") {
        return;
    }
    story_line("Fixing invalid User=session in D-Bus activation file…");
    let cleaned: String = text
        .lines()
        .filter(|l| l.trim() != "User=session")
        .collect::<Vec<_>>()
        .join("\n")
        + "\n";
    if std::fs::write(path, &cleaned).is_ok() {
        return;
    }
    let _ = run_status(Command::new("sudo").args(["sed", "-i", "/^User=session$/d", path]));
}

fn ensure_config_dirs() {
    let Ok(home) = env::var("HOME") else {
        return;
    };
    let idle_cfg = format!("{home}/.config/idle");
    let _ = std::fs::create_dir_all(&idle_cfg);
    let _ = std::fs::create_dir_all(format!("{home}/.config/idlescreen"));
    if let Ok(entries) = std::fs::read_dir(&idle_cfg) {
        for e in entries.flatten() {
            if e.file_name().to_string_lossy().starts_with("config.tmp.") {
                let _ = std::fs::remove_file(e.path());
            }
        }
    }
}

pub fn start_daemon() -> bool {
    story_line("Ensuring ~/.config/idle exists (daemon config dir)…");
    ensure_config_dirs();
    fix_dbus_activation_file();
    std::thread::sleep(std::time::Duration::from_millis(300));
    story_line("Reloading user systemd units…");
    let _ = run_status(Command::new("systemctl").args(["--user", "daemon-reload"]));
    let _ = run_status(Command::new("systemctl").args([
        "--user",
        "reset-failed",
        "idle-daemon.service",
    ]));
    story_line("systemctl --user enable idle-daemon.service…");
    let _ = run_status(Command::new("systemctl").args([
        "--user",
        "enable",
        "idle-daemon.service",
    ]));
    // Clean restart so a dying upgrade process releases the bus name.
    story_line("systemctl --user restart idle-daemon.service…");
    if !run_status(Command::new("systemctl").args([
        "--user",
        "restart",
        "idle-daemon.service",
    ])) {
        warn("restart not active yet — stop + start…");
        let _ = run_status(Command::new("systemctl").args(["--user", "stop", "idle-daemon.service"]));
        std::thread::sleep(std::time::Duration::from_millis(400));
        let _ = run_status(Command::new("systemctl").args([
            "--user",
            "reset-failed",
            "idle-daemon.service",
        ]));
        let _ = run_status(Command::new("systemctl").args(["--user", "start", "idle-daemon.service"]));
    }
    for _ in 0..30 {
        if daemon_ready() {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(200));
    }
    if daemon_ready() {
        ok(&format!(
            "idle-daemon.service is {C_GREEN}{C_BOLD}active{C_RESET} (D-Bus name claimed)"
        ));
        return true;
    }
    if !bus_name_up() {
        warn("user unit not ready — trying one-shot idle-daemon spawn…");
        let _ = Command::new("idle-daemon").arg("daemon").spawn();
        std::thread::sleep(std::time::Duration::from_millis(800));
        let _ = run_status(Command::new("systemctl").args([
            "--user",
            "reset-failed",
            "idle-daemon.service",
        ]));
        let _ = run_status(Command::new("systemctl").args(["--user", "start", "idle-daemon.service"]));
        std::thread::sleep(std::time::Duration::from_millis(500));
    }
    if daemon_ready() || bus_name_up() {
        ok(&format!(
            "idle-daemon is up ({C_GREEN}{C_BOLD}bus/service{C_RESET})"
        ));
        return true;
    }
    warn("idle-daemon D-Bus service is not ready.");
    println!("    systemctl --user status idle-daemon.service");
    println!("    journalctl --user -u idle-daemon.service -n 30 --no-pager");
    println!("    or: idlescreen doctor --fix");
    false
}
