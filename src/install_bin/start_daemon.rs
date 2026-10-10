// SPDX-License-Identifier: Apache-2.0

//! Post-deploy: enable/start idle-daemon and claim the session bus name.

use std::env;
use std::process::Command;

use super::host::{run_capture, run_status};
use super::ui::{C_BOLD, C_GREEN, C_RESET, ok, story_line, warn};

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

/// Ensure D-Bus service file exists and has no invalid User=session.
fn fix_dbus_activation_file() {
    let path = "/usr/share/dbus-1/services/io.github.idlescreen.Idle.service";
    let contents = "[D-BUS Service]\nName=io.github.idlescreen.Idle\nExec=/usr/bin/idlescreen daemon\nSystemdService=idlescreen.service\n";
    if !std::path::Path::new(path).exists() {
        story_line("Installing missing D-Bus activation file…");
        if std::fs::write(path, contents).is_err() {
            let tmp = format!("/tmp/io.github.idlescreen.Idle.service.{}", std::process::id());
            if std::fs::write(&tmp, contents).is_ok() {
                let _ = run_status(Command::new("sudo").args(["install", "-Dm644", &tmp, path]));
                let _ = std::fs::remove_file(&tmp);
            }
        }
        return;
    }
    let Ok(text) = std::fs::read_to_string(path) else {
        return;
    };
    if text.lines().any(|l| l.trim() == "User=session") || text.contains("idle-daemon") {
        story_line("Fixing invalid User=session or idle-daemon in D-Bus activation file…");
        let cleaned: String = text
            .lines()
            .filter(|l| l.trim() != "User=session")
            .map(|l| l.replace("idle-daemon", "idlescreen"))
            .collect::<Vec<_>>()
            .join("\n")
            + "\n";
        if std::fs::write(path, &cleaned).is_ok() {
            return;
        }
        let _ = run_status(Command::new("sudo").args(["sed", "-i", "-e", "/^User=session$/d", "-e", "s/idle-daemon/idlescreen/g", path]));
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
    let idle_file = std::path::Path::new(&idle_cfg).join("config.yaml");
    let idlescreen_file = std::path::Path::new(&idlescreen_cfg).join("config.yaml");
    let etc_xdg_idlescreen = std::path::Path::new("/etc/xdg/idlescreen/config.yaml");
    let etc_idlescreen = std::path::Path::new("/etc/idlescreen/config.yaml");
    let etc_idle = std::path::Path::new("/etc/idle/config.yaml");

    for p in [
        &idlescreen_file,
        &idle_file,
        etc_xdg_idlescreen,
        etc_idlescreen,
        etc_idle,
    ] {
        if p.is_file() {
            story_line(&format!(
                "Preserving existing configuration: {}",
                p.display()
            ));
        }
    }

    let sys_file = if etc_xdg_idlescreen.is_file() {
        Some(etc_xdg_idlescreen)
    } else if etc_idlescreen.is_file() {
        Some(etc_idlescreen)
    } else if etc_idle.is_file() {
        Some(etc_idle)
    } else {
        None
    };

    if idlescreen_file.is_file() {
        if !idle_file.exists() {
            let _ = std::fs::copy(&idlescreen_file, &idle_file);
        }
    } else if idle_file.is_file() {
        if !idlescreen_file.exists() {
            let _ = std::fs::copy(&idle_file, &idlescreen_file);
        }
    } else if let Some(sys) = sys_file {
        if !idlescreen_file.exists() {
            let _ = std::fs::copy(sys, &idlescreen_file);
        }
        if !idle_file.exists() {
            let _ = std::fs::copy(sys, &idle_file);
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
        let _ = run_status(Command::new("systemctl").args([
            "--user",
            "stop",
            "idle-daemon.service",
        ]));
        let _ = run_status(Command::new("systemctl").args([
            "--user",
            "disable",
            "idle-daemon.service",
        ]));
        let _ = run_status(Command::new("systemctl").args([
            "--user",
            "reset-failed",
            "idlescreen.service",
        ]));
        story_line("systemctl --user enable --now idlescreen.service…");
        let _ =
            run_status(Command::new("systemctl").args(["--user", "enable", "--now", "idlescreen.service"]));
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
