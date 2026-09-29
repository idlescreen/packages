// SPDX-License-Identifier: Apache-2.0

//! Terminal styling helpers for the installer.

use std::thread::sleep;
use std::time::Duration;

pub const C_ORANGE: &str = "\x1b[38;5;208m";
pub const C_CYAN: &str = "\x1b[38;5;51m";
pub const C_GREEN: &str = "\x1b[38;5;82m";
pub const C_YELLOW: &str = "\x1b[38;5;220m";
pub const C_MAGENTA: &str = "\x1b[38;5;213m";
pub const C_DIM: &str = "\x1b[38;5;242m";
pub const C_BOLD: &str = "\x1b[1m";
pub const C_RESET: &str = "\x1b[0m";

pub fn pause(ms: u64) {
    sleep(Duration::from_millis(ms));
}

pub fn say(line: &str) {
    println!("{line}");
}

pub fn story_line(msg: &str) {
    println!("  {C_MAGENTA}›{C_RESET} {C_DIM}{msg}{C_RESET}");
    pause(200);
}

pub fn ok(msg: &str) {
    println!(" {C_GREEN}✔{C_RESET} {msg}");
}

pub fn warn(msg: &str) {
    println!(" {C_YELLOW}!{C_RESET} {msg}");
}

pub fn err(msg: &str) {
    eprintln!(" {C_YELLOW}ERROR:{C_RESET} {msg}");
}

pub fn step(msg: &str) {
    println!();
    println!(" {C_CYAN}{C_BOLD}{msg}{C_RESET}");
}
