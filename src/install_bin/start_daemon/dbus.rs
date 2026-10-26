// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 IdleScreen

//! Installation and repair of the D-Bus activation file.

use std::process::Command;

use super::super::host::run_status;
use super::super::ui::story_line;

fn stage_temp_file(label: &str, contents: &str) -> Option<std::path::PathBuf> {
    use std::io::Write;
    let base = std::path::Path::new(label)
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "staged".to_string());
    for attempt in 0..8u32 {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.subsec_nanos())
            .unwrap_or(0);
        let path =
            std::env::temp_dir().join(format!("{base}.{}.{nanos}.{attempt}", std::process::id()));
        match std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)
        {
            Ok(mut f) => {
                if f.write_all(contents.as_bytes()).is_ok() {
                    return Some(path);
                }
                let _ = std::fs::remove_file(&path);
                return None;
            }
            Err(_) => continue,
        }
    }
    None
}

/// Ensure D-Bus service file exists and has no invalid User=session.
pub(super) fn fix_dbus_activation_file() {
    let path = "/usr/share/dbus-1/services/io.github.idlescreen.Idle.service";
    let contents = "[D-BUS Service]\nName=io.github.idlescreen.Idle\nExec=/usr/bin/idlescreen daemon\nSystemdService=idlescreen.service\n";
    if !std::path::Path::new(path).exists() {
        story_line("Installing missing D-Bus activation file…");
        if std::fs::write(path, contents).is_err() {
            // Stage the file in a uniquely named temp file. `create_new`
            // refuses an existing path (including a symlink planted by
            // another user in the world-writable temp dir).
            let staged = stage_temp_file(path, contents);
            if let Some(tmp) = staged {
                let _ = run_status(
                    Command::new("sudo")
                        .args(["install", "-Dm644"])
                        .arg(&tmp)
                        .arg(path),
                );
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
        let _ = run_status(Command::new("sudo").args([
            "sed",
            "-i",
            "-e",
            "/^User=session$/d",
            "-e",
            "s/idle-daemon/idlescreen/g",
            path,
        ]));
    }
}
