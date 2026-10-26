// SPDX-License-Identifier: Apache-2.0

//! Post-deploy: enable/start idle-daemon and claim the session bus name.

use std::env;
use std::process::Command;

mod dbus;

use super::host::{run_capture, run_status};
use super::ui::{C_BOLD, C_GREEN, C_RESET, ok, story_line, warn};
use dbus::fix_dbus_activation_file;

fn unit_active() -> bool {
    if !run_status(Command::new("which").arg("systemctl")) {
        return false;
    }
    run_capture(Command::new("systemctl").args(["--user", "is-active", "idlescreen.service"]))
        .map(|s| s == "active")
        .unwrap_or(false)
}

fn bus_name_up() -> bool {
    run_status(Command::new("busctl").args([
        "--user",
        "--timeout=1",
        "status",
        "io.github.idlescreen.Idle",
    ]))
}

fn daemon_ready() -> bool {
    if run_status(Command::new("which").arg("systemctl")) {
        unit_active() && bus_name_up()
    } else {
        bus_name_up()
    }
}

fn ensure_config_dirs() {
    let Ok(home) = env::var("HOME") else {
        return;
    };
    let idle_cfg = format!("{home}/.config/idle");
    let idlescreen_cfg = format!("{home}/.config/idlescreen");
    let _ = std::fs::create_dir_all(&idle_cfg);
    let _ = std::fs::create_dir_all(&idlescreen_cfg);
    for dir in [&idle_cfg, &idlescreen_cfg] {
        if let Ok(entries) = std::fs::read_dir(dir) {
            for e in entries.flatten() {
                if e.file_name().to_string_lossy().starts_with("config.tmp.") {
                    let _ = std::fs::remove_file(e.path());
                }
            }
        }
    }
    let idlescreen_toml = std::path::Path::new(&idlescreen_cfg).join("config.toml");
    let idlescreen_file = std::path::Path::new(&idlescreen_cfg).join("config.yaml");
    let idle_file = std::path::Path::new(&idle_cfg).join("config.yaml");
    let etc_xdg_toml = std::path::Path::new("/etc/xdg/idlescreen/config.toml");
    let etc_toml = std::path::Path::new("/etc/idlescreen/config.toml");
    let etc_xdg_yaml = std::path::Path::new("/etc/xdg/idlescreen/config.yaml");
    let etc_yaml = std::path::Path::new("/etc/idlescreen/config.yaml");
    let etc_idle = std::path::Path::new("/etc/idle/config.yaml");

    for p in [
        idlescreen_toml.as_path(),
        idlescreen_file.as_path(),
        idle_file.as_path(),
        etc_xdg_toml,
        etc_toml,
        etc_xdg_yaml,
        etc_yaml,
        etc_idle,
    ] {
        if p.is_file() {
            story_line(&format!(
                "Preserving existing configuration: {}",
                p.display()
            ));
        }
    }

    if idlescreen_file.is_file() && !idle_file.exists() {
        let _ = std::fs::copy(&idlescreen_file, &idle_file);
    } else if idle_file.is_file() && !idlescreen_file.exists() {
        let _ = std::fs::copy(&idle_file, &idlescreen_file);
    }
    if !idlescreen_toml.exists() && !idlescreen_file.exists() {
        if let Some(sys_toml) = [etc_xdg_toml, etc_toml].into_iter().find(|p| p.is_file()) {
            let _ = std::fs::copy(sys_toml, &idlescreen_toml);
        } else if let Some(sys_yaml) = [etc_xdg_yaml, etc_yaml, etc_idle]
            .into_iter()
            .find(|p| p.is_file())
        {
            let _ = std::fs::copy(sys_yaml, &idlescreen_file);
        } else {
            let _ = std::fs::write(
                &idlescreen_toml,
                "[general]\nidle_timeout_secs = 300\n\n[saver]\nactive = \"ascii\"\n",
            );
        }
    }
}

pub fn start_daemon() -> bool {
    story_line("Ensuring ~/.config/idle exists (daemon config dir)…");
    ensure_config_dirs();
    fix_dbus_activation_file();
    std::thread::sleep(std::time::Duration::from_millis(300));
    let has_systemd = run_status(Command::new("which").arg("systemctl"));
    if has_systemd {
        story_line("Reloading user systemd units…");
        let _ = run_status(Command::new("systemctl").args(["--user", "daemon-reload"]));
        let _ =
            run_status(Command::new("systemctl").args(["--user", "stop", "idle-daemon.service"]));
        let _ = run_status(Command::new("systemctl").args([
            "--user",
            "disable",
            "idle-daemon.service",
        ]));
        let _ =
            run_status(Command::new("systemctl").args(["--user", "stop", "idlescreen.service"]));
        let _ = Command::new("pkill").args(["-x", "idlescreen"]).status();
        let _ = Command::new("pkill")
            .args(["-f", "/usr/bin/idlescreen daemon"])
            .status();
        let _ = Command::new("pkill").args(["-x", "idle-daemon"]).status();
        let _ = Command::new("pkill")
            .args(["-f", "/usr/bin/idle-daemon"])
            .status();
        let _ = run_status(Command::new("systemctl").args([
            "--user",
            "reset-failed",
            "idlescreen.service",
        ]));
        story_line("systemctl --user enable --now idlescreen.service…");
        let _ = run_status(Command::new("systemctl").args([
            "--user",
            "enable",
            "--now",
            "idlescreen.service",
        ]));
        // Clean restart so a dying upgrade process releases the bus name.
        story_line("systemctl --user restart idlescreen.service…");
        if !run_status(Command::new("systemctl").args(["--user", "restart", "idlescreen.service"]))
        {
            warn("restart not active yet — stop + start…");
            let _ = run_status(Command::new("systemctl").args([
                "--user",
                "stop",
                "idlescreen.service",
            ]));
            std::thread::sleep(std::time::Duration::from_millis(400));
            let _ = run_status(Command::new("systemctl").args([
                "--user",
                "reset-failed",
                "idlescreen.service",
            ]));
            let _ = run_status(Command::new("systemctl").args([
                "--user",
                "start",
                "idlescreen.service",
            ]));
        }
    } else {
        story_line("Starting idlescreen daemon…");
        let _ = Command::new("idlescreen").arg("daemon").spawn();
    }
    for _ in 0..30 {
        if daemon_ready() {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(200));
    }
    if daemon_ready() {
        ok(&format!(
            "idlescreen is {C_GREEN}{C_BOLD}active{C_RESET} (D-Bus name claimed)"
        ));
        return true;
    }
    if !bus_name_up() {
        warn("trying one-shot idlescreen daemon spawn…");
        let _ = Command::new("idlescreen").arg("daemon").spawn();
        std::thread::sleep(std::time::Duration::from_millis(800));
        if has_systemd {
            let _ = run_status(Command::new("systemctl").args([
                "--user",
                "reset-failed",
                "idlescreen.service",
            ]));
            let _ = run_status(Command::new("systemctl").args([
                "--user",
                "start",
                "idlescreen.service",
            ]));
            std::thread::sleep(std::time::Duration::from_millis(500));
        }
    }
    if daemon_ready() || bus_name_up() {
        ok(&format!(
            "idlescreen is up ({C_GREEN}{C_BOLD}bus/service{C_RESET})"
        ));
        return true;
    }
    warn("idlescreen D-Bus service is not ready.");
    println!("    systemctl --user status idlescreen.service");
    println!("    journalctl --user -u idlescreen.service -n 30 --no-pager");
    println!("    or: idlescreen doctor --fix");
    false
}
