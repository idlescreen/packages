use std::env;
use std::process::Command;
use std::thread::sleep;
use std::time::Duration;

fn main() {
    // ANSI Color Tokens
    let orange = "\x1b[38;5;208m";
    let cyan = "\x1b[38;5;51m";
    let green = "\x1b[38;5;82m";
    let yellow = "\x1b[38;5;220m";
    let dim = "\x1b[38;5;242m";
    let bold = "\x1b[1m";
    let reset = "\x1b[0m";

    // 1. Epic ASCII Art Banner
    println!("\n{}", orange);
    println!(r#"  ___    _ _      ____  ___ ___  ___  ___ _  _"#);
    println!(r#" |_ _|__| | | ___/ ___|/ __/ _ \| _ \/ __| \| |"#);
    println!(r#"  | |/ _` | |/ _ \___ \ (_|  __/|   / (__| .` |"#);
    println!(r#" |___\__,_|_|_|\___|___/\___\___|_|_\\___|_|\_|"#);
    println!("{}", reset);
    println!(" {bold}High-Performance Ambient Screensavers for Wayland{reset}");
    println!(" {dim}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{reset}\n");

    sleep(Duration::from_millis(200));

    // Phase 1: Environment & System Audit
    println!(" {cyan}[1/4]{reset} {bold}Auditing System Environment...{reset}");
    let desktop = env::var("XDG_CURRENT_DESKTOP").unwrap_or_else(|_| "Wayland Desktop".into());
    let arch = env::consts::ARCH;
    let is_dnf = std::path::Path::new("/usr/bin/dnf").exists();
    let is_apt = std::path::Path::new("/usr/bin/apt-get").exists();
    let is_cosmic = desktop.contains("COSMIC") || std::path::Path::new("/usr/bin/cosmic-panel").exists();

    println!("       ├─ Architecture:  {green}{arch}{reset}");
    println!("       ├─ Environment:   {green}{desktop}{reset}");
    if is_dnf {
        println!("       └─ Package Host:  {green}DNF (Fedora / RHEL / Rocky){reset}");
    } else if is_apt {
        println!("       └─ Package Host:  {green}APT (Debian / Ubuntu / Pop!_OS){reset}");
    } else {
        println!("       └─ Package Host:  {yellow}Generic / Manual Target{reset}");
    }

    sleep(Duration::from_millis(250));

    // Phase 2: Repository Integration & Keyring Handshake
    println!("\n {cyan}[2/4]{reset} {bold}Connecting Repository & Cryptographic Keys...{reset}");
    if is_dnf {
        println!("       ├─ Fetching GPG Keyring & DNF Repository Manifest...");
        let _ = Command::new("sudo")
            .args([
                "curl",
                "-fsSL",
                "https://idlescreen.github.io/packages/rpm/idlescreen.repo",
                "-o",
                "/etc/yum.repos.d/idlescreen.repo",
            ])
            .status();
        println!("       └─ {green}Repository configured at /etc/yum.repos.d/idlescreen.repo{reset}");

        sleep(Duration::from_millis(200));

        // Phase 3: Package Installation — real modular NEVRAs, not legacy "idlescreen" alone.
        println!("\n {cyan}[3/4]{reset} {bold}Deploying IdleScreen Core Engine & Modules...{reset}");
        println!("       ├─ Executing dnf package installation...");
        let mut pkgs = vec![
            "idle-daemon",
            "idle-cli",
            "idle-savers",
            "idle-tui",
        ];
        if is_cosmic {
            pkgs.push("idle-cosmic");
        }
        let st = Command::new("sudo")
            .arg("dnf")
            .arg("install")
            .arg("-y")
            .args(&pkgs)
            .status();
        if st.map(|s| !s.success()).unwrap_or(true) {
            eprintln!("       └─ {yellow}ERROR: dnf install failed.{reset}");
            std::process::exit(1);
        }
        let verify = Command::new("rpm")
            .args(["-q", "idle-daemon", "idle-cli"])
            .status();
        if verify.map(|s| !s.success()).unwrap_or(true) {
            eprintln!("       └─ {yellow}ERROR: idle-daemon / idle-cli missing after install.{reset}");
            std::process::exit(1);
        }
        println!("       └─ {green}Core engine binaries & visual modules installed.{reset}");
    } else if is_apt {
        println!("       ├─ Provisioning APT keyring folder...");
        let _ = Command::new("sudo")
            .args(["mkdir", "-p", "/etc/apt/keyrings"])
            .status();

        println!("       ├─ Fetching GPG signing key...");
        let _ = Command::new("sh")
            .arg("-c")
            .arg("curl -fsSL https://idlescreen.github.io/packages/idlescreen-keyring.gpg | sudo tee /etc/apt/keyrings/idlescreen-keyring.gpg >/dev/null")
            .status();

        println!("       ├─ Adding APT repository source list...");
        let _ = Command::new("sh")
            .arg("-c")
            .arg("echo 'deb [signed-by=/etc/apt/keyrings/idlescreen-keyring.gpg] https://idlescreen.github.io/packages/apt/ stable main' | sudo tee /etc/apt/sources.list.d/idlescreen.list >/dev/null")
            .status();

        println!("       └─ Updating package index...");
        let _ = Command::new("sudo").args(["apt-get", "update"]).status();

        sleep(Duration::from_millis(200));

        // Phase 3: Package Installation — real modular NEVRAs.
        println!("\n {cyan}[3/4]{reset} {bold}Deploying IdleScreen Core Engine & Modules...{reset}");
        println!("       ├─ Executing apt package installation...");
        let mut pkgs = vec![
            "idle-daemon",
            "idle-cli",
            "idle-savers",
            "idle-tui",
        ];
        if is_cosmic {
            pkgs.push("idle-cosmic");
        }
        let st = Command::new("sudo")
            .arg("apt-get")
            .arg("install")
            .arg("-y")
            .args(&pkgs)
            .status();
        if st.map(|s| !s.success()).unwrap_or(true) {
            // idle-tui may be missing from older APT indexes
            let mut retry = vec!["idle-daemon", "idle-cli", "idle-savers"];
            if is_cosmic {
                retry.push("idle-cosmic");
            }
            let st2 = Command::new("sudo")
                .arg("apt-get")
                .arg("install")
                .arg("-y")
                .args(&retry)
                .status();
            if st2.map(|s| !s.success()).unwrap_or(true) {
                eprintln!("       └─ {yellow}ERROR: apt-get install failed.{reset}");
                std::process::exit(1);
            }
        }
        let verify = Command::new("dpkg-query")
            .args(["-W", "idle-daemon", "idle-cli"])
            .status();
        if verify.map(|s| !s.success()).unwrap_or(true) {
            eprintln!("       └─ {yellow}ERROR: idle-daemon / idle-cli missing after install.{reset}");
            std::process::exit(1);
        }
        println!("       └─ {green}Core engine binaries & visual modules installed.{reset}");
    } else {
        println!(" {yellow}⚠️  Unsupported package manager. Please check manual installation at https://idlescreen.github.io/packages/{reset}");
        std::process::exit(1);
    }

    sleep(Duration::from_millis(250));

    // Phase 4: Service Provisioning & Systemd Activation
    println!("\n {cyan}[4/4]{reset} {bold}Provisioning User Configuration & Daemon Unit...{reset}");
    if let Ok(home) = env::var("HOME") {
        let _ = std::fs::create_dir_all(format!("{home}/.config/idle"));
        let _ = std::fs::create_dir_all(format!("{home}/.config/idlescreen"));
        println!("       ├─ Config Directory: {green}{home}/.config/idlescreen/{reset}");
    }

    let _ = Command::new("systemctl")
        .args(["--user", "daemon-reload"])
        .output();

    let _ = Command::new("systemctl")
        .args(["--user", "reset-failed", "idle-daemon.service"])
        .output();

    let _ = Command::new("systemctl")
        .args(["--user", "enable", "--now", "idle-daemon.service"])
        .output();

    let daemon_active = Command::new("systemctl")
        .args(["--user", "is-active", "idle-daemon.service"])
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim() == "active")
        .unwrap_or(false);

    if daemon_active {
        println!("       └─ Systemd Service: {green}Active & Running (idle-daemon.service){reset}");
    } else {
        println!("       └─ Systemd Service: {yellow}Configured (idle-daemon.service){reset}");
    }

    sleep(Duration::from_millis(300));

    // Phase 5: Final Victory Summary Banner
    println!("\n {green}{bold}✓ Installation Complete! Welcome to IdleScreen.{reset}");
    println!(" {dim}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{reset}");

    if is_cosmic {
        println!(" {orange}📱 COSMIC Desktop Integration:{reset} Panel Applet Enabled");
    }

    println!("\n {bold}Quick Start Commands:{reset}");
    println!("   {cyan}idlescreen tui{reset}       Launch live interactive terminal UI dashboard");
    println!("   {cyan}idlescreen status{reset}    Check active screensaver & daemon status");
    println!("   {cyan}idlescreen doctor{reset}    Run system health & Wayland diagnostic check");
    println!("\n {dim}Desktop Application Launcher entry also available in your application menu.{reset}");
    println!(" {dim}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{reset}\n");
}
