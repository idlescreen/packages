// SPDX-License-Identifier: Apache-2.0

//! Final summary screen (truthful post-deploy counts).

use super::pkg::{Survey, pkg_present};
use super::ui::{C_BOLD, C_CYAN, C_DIM, C_GREEN, C_ORANGE, C_RESET, C_YELLOW};

const REPO_BASE: &str = "https://idlescreen.github.io/packages";

#[allow(clippy::too_many_arguments)]
pub fn print_victory(
    os_name: &str,
    arch: &str,
    de_label: &str,
    channel: &str,
    cosmic: bool,
    dnf: bool,
    pkgs: &[&str],
    present: &[&str],
    missing: &[&str],
    survey: &Survey,
    active: bool,
) {
    let (banner, note) = idlescreen_packages::victory_banner(missing.is_empty(), active);
    // One pure helper builds every row so left/right borders stay flush and the
    // title is truly centered (not left-padded in a fixed 20-col field).
    let box_lines = idlescreen_packages::format_victory_box(banner);

    println!();
    println!("  {C_GREEN}{C_BOLD}");
    for line in &box_lines {
        println!("        {line}");
    }
    println!("  {C_RESET}");
    println!("  {C_DIM}note{C_RESET}     {note}");
    println!("  {C_DIM}host{C_RESET}     {os_name}  ({arch})");
    println!("  {C_DIM}desktop{C_RESET}  {de_label}");
    println!("  {C_DIM}channel{C_RESET}  {channel}");
    println!("  {C_DIM}plan{C_RESET}     {}", pkgs.join(" "));
    println!(
        "  {C_DIM}present{C_RESET}  {}/{} planned package(s) on the system now",
        present.len(),
        pkgs.len()
    );
    if !survey.upgrade.is_empty() {
        println!(
            "  {C_DIM}survey{C_RESET}   {} were outdated before deploy (upgrade was requested)",
            survey.upgrade.len()
        );
    }
    if !survey.install.is_empty() {
        println!(
            "  {C_DIM}survey{C_RESET}   {} were missing before deploy (install was requested)",
            survey.install.len()
        );
    }
    if !missing.is_empty() {
        println!("  {C_YELLOW}missing{C_RESET}  {}", missing.join(" "));
    }
    if let Some(line) =
        idlescreen_packages::format_cosmic_line(cosmic, pkg_present("idle-cosmic", dnf))
    {
        // format_cosmic_line returns "COSMIC  …" — color the label.
        if let Some(rest) = line.strip_prefix("COSMIC  ") {
            println!("  {C_ORANGE}COSMIC{C_RESET}  {rest}");
        } else {
            println!("  {C_ORANGE}{line}{C_RESET}");
        }
    }
    println!();
    println!("  {C_BOLD}Quick start{C_RESET}");
    println!("    {C_CYAN}idlescreen tui{C_RESET}        interactive dashboard");
    println!("    {C_CYAN}idlescreen status{C_RESET}     daemon + saver state");
    println!("    {C_CYAN}idlescreen preview beams{C_RESET}  try an effect");
    println!("    {C_CYAN}idlescreen doctor{C_RESET}     system diagnostics");
    println!();
    println!("  {C_BOLD}Remove{C_RESET}");
    if dnf {
        println!("    {C_CYAN}sudo dnf remove idlescreen{C_RESET}");
    } else {
        println!("    {C_CYAN}sudo apt remove idlescreen{C_RESET}");
    }
    println!(
        "    {C_DIM}# 2.6+ also removes modules, savers, idle-cosmic, repo drop-in{C_RESET}"
    );
    println!();
    println!("  {C_DIM}docs  {C_RESET}https://idlescreen.github.io");
    println!("  {C_DIM}pkgs  {C_RESET}{REPO_BASE}/");
    println!("  {C_DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{C_RESET}");
    println!();
}
