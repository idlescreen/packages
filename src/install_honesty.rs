//! Pure installer copy and survey logic — unit-tested so the UI cannot lie.
// SPDX-License-Identifier: Apache-2.0

use crate::compare_versions;
use std::cmp::Ordering;

/// Core packages always requested (every DE).
pub const CORE_PACKAGES: &[&str] = &[
    "idle-daemon",
    "idle-cli",
    "idle-savers",
    "idle-tui",
    "idlescreen",
];

/// Extra package only when COSMIC is detected.
pub const COSMIC_EXTRA: &str = "idle-cosmic";

/// Truthful DNF channel disclaimer (packages GPG-checked; repo metadata not).
pub const DNF_GPG_DISCLAIMER: &str = "package gpgcheck=1 · repo_gpgcheck=0";

/// Survey classification for one package (no I/O).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SurveyClass {
    /// Not installed → will attempt install.
    Install,
    /// Installed older than channel → will attempt upgrade.
    Upgrade,
    /// Installed and matches (or is not older than) channel.
    Current,
    /// Installed but channel version unknown — do not claim "matches channel".
    CurrentUnknown,
}

/// True when installed version is strictly older than candidate.
pub fn version_is_older(installed: &str, candidate: &str) -> bool {
    !installed.is_empty()
        && !candidate.is_empty()
        && compare_versions(installed, candidate) == Ordering::Less
}

/// Classify one package from optional installed + candidate versions.
pub fn classify_package(installed: Option<&str>, candidate: Option<&str>) -> SurveyClass {
    match (installed, candidate) {
        (None, _) => SurveyClass::Install,
        (Some(i), Some(c)) if version_is_older(i, c) => SurveyClass::Upgrade,
        (Some(_), Some(_)) => SurveyClass::Current,
        (Some(_), None) => SurveyClass::CurrentUnknown,
    }
}

/// Package list for a desktop profile (pure).
pub fn packages_for_profile(cosmic: bool) -> Vec<&'static str> {
    let mut p: Vec<&'static str> = CORE_PACKAGES.to_vec();
    if cosmic {
        p.push(COSMIC_EXTRA);
    }
    p
}

/// Honest one-liner describing the package plan (no DE gets a fake "full" vs "core" split).
pub fn format_plan_blurb(cosmic: bool) -> String {
    if cosmic {
        format!(
            "Core stack (all DEs): {}  ·  COSMIC: also {}",
            CORE_PACKAGES.join(" "),
            COSMIC_EXTRA
        )
    } else {
        format!("Core stack (all DEs): {}", CORE_PACKAGES.join(" "))
    }
}

/// Human survey row without ANSI (for goldens / tests).
pub fn format_survey_row_plain(
    pkg: &str,
    class: SurveyClass,
    installed: Option<&str>,
    candidate: Option<&str>,
) -> String {
    match class {
        SurveyClass::Install => format!("{pkg}  not installed  →  install"),
        SurveyClass::Upgrade => format!(
            "{pkg}  {}  →  {}  upgrade",
            installed.unwrap_or("?"),
            candidate.unwrap_or("?")
        ),
        SurveyClass::Current => format!(
            "{pkg}  {}  matches channel (={})",
            installed.unwrap_or("?"),
            candidate.unwrap_or("?")
        ),
        SurveyClass::CurrentUnknown => format!(
            "{pkg}  {}  (installed; channel version unknown)",
            installed.unwrap_or("?")
        ),
    }
}

/// Summary lines after survey (honest wording: "will attempt", not "will raise").
pub fn format_survey_summary(upgrade_n: usize, install_n: usize) -> Vec<String> {
    let mut lines = Vec::new();
    if upgrade_n > 0 {
        lines.push(format!(
            "Survey: {upgrade_n} outdated module(s) — will attempt upgrade to channel."
        ));
    }
    if install_n > 0 {
        lines.push(format!(
            "Survey: {install_n} missing module(s) — will attempt install."
        ));
    }
    if upgrade_n == 0 && install_n == 0 {
        lines.push("Survey: planned modules look current — will still re-sync (may no-op).".into());
    }
    lines
}

/// Victory banner title + note (truthful post-deploy).
pub fn victory_banner(all_present: bool, daemon_active: bool) -> (&'static str, &'static str) {
    if all_present && daemon_active {
        ("INSTALL FINISHED", "packages present · daemon active")
    } else if all_present {
        (
            "PACKAGES INSTALLED",
            "daemon not active yet — see notes above",
        )
    } else {
        (
            "INSTALL PARTIAL",
            "some planned packages missing — see list above",
        )
    }
}

/// Fixed-width box content: character columns between the two `║` borders.
/// All victory box rows must share the same total char length so the right
/// edge stays flush in a monospace terminal.
pub const VICTORY_BOX_INNER: usize = 54;

/// Ornament used around the title. Prefer a single-cell glyph; `✦` is
/// East-Asian-width Neutral and renders as 1 cell on typical Linux TTYs.
pub const VICTORY_ORNAMENT: char = '✦';

/// Center `text` in exactly `width` character columns (pad/truncate by char count).
pub fn center_in_width(text: &str, width: usize) -> String {
    let chars: Vec<char> = text.chars().collect();
    if chars.len() >= width {
        return chars.into_iter().take(width).collect();
    }
    let pad = width - chars.len();
    let left = pad / 2;
    let right = pad - left;
    format!("{}{}{}", " ".repeat(left), text, " ".repeat(right))
}

/// Inner body only (no borders): ornament + title + ornament, centered.
pub fn format_victory_title_body(title: &str) -> String {
    let label = format!("{VICTORY_ORNAMENT}  {title}  {VICTORY_ORNAMENT}");
    center_in_width(&label, VICTORY_BOX_INNER)
}

/// One content row: `║` + centered title body + `║`.
pub fn format_victory_box_title_row(title: &str) -> String {
    format!("║{}║", format_victory_title_body(title))
}

/// Full victory box (5 lines, no leading indent, no ANSI). All lines equal width.
pub fn format_victory_box(title: &str) -> [String; 5] {
    let bar = "═".repeat(VICTORY_BOX_INNER);
    let blank = " ".repeat(VICTORY_BOX_INNER);
    [
        format!("╔{bar}╗"),
        format!("║{blank}║"),
        format_victory_box_title_row(title),
        format!("║{blank}║"),
        format!("╚{bar}╝"),
    ]
}

/// Border line for the victory box (top/bottom style without corners for width check).
pub fn victory_box_border_inner_width() -> usize {
    VICTORY_BOX_INNER
}

/// Strip simple CSI ANSI sequences for width measurement.
pub fn strip_ansi(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\u{1b}' {
            if chars.peek() == Some(&'[') {
                chars.next();
                for x in chars.by_ref() {
                    if x.is_ascii_alphabetic() {
                        break;
                    }
                }
            }
            continue;
        }
        out.push(c);
    }
    out
}

/// True if all non-empty lines have the same character length after stripping ANSI.
pub fn lines_same_width(lines: &[&str]) -> bool {
    let widths: Vec<usize> = lines
        .iter()
        .map(|l| strip_ansi(l).chars().count())
        .filter(|w| *w > 0)
        .collect();
    match widths.as_slice() {
        [] | [_] => true,
        [w, rest @ ..] => rest.iter().all(|x| x == w),
    }
}

/// Deploy result line (honest).
pub fn format_deploy_result(present: usize, planned: usize) -> String {
    if present >= planned && planned > 0 {
        format!("Deploy finished — all {present} planned package(s) present.")
    } else if planned == 0 {
        "Deploy finished — empty plan.".into()
    } else {
        format!("Deploy finished — {present}/{planned} planned package(s) present.")
    }
}

/// COSMIC line after deploy (truthful about package presence, not panel dock state).
pub fn format_cosmic_line(planned: bool, installed: bool) -> Option<String> {
    if !planned {
        return None;
    }
    if installed {
        Some(
            "COSMIC  Package idle-cosmic is installed — add from panel settings if not docked."
                .into(),
        )
    } else {
        Some("COSMIC  idle-cosmic was planned but is not installed.".into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_is_older_basic() {
        assert!(version_is_older("2.5.9-1", "2.5.10-1"));
        assert!(!version_is_older("2.5.10-1", "2.5.10-1"));
        assert!(!version_is_older("2.5.10-1", "2.5.9-1"));
        assert!(!version_is_older("", "1.0"));
        assert!(!version_is_older("1.0", ""));
    }

    #[test]
    fn classify_install_upgrade_current() {
        assert_eq!(classify_package(None, Some("1.0")), SurveyClass::Install);
        assert_eq!(
            classify_package(Some("1.0-1"), Some("1.1-1")),
            SurveyClass::Upgrade
        );
        assert_eq!(
            classify_package(Some("1.1-1"), Some("1.1-1")),
            SurveyClass::Current
        );
        assert_eq!(
            classify_package(Some("1.2-1"), Some("1.1-1")),
            SurveyClass::Current
        );
        assert_eq!(
            classify_package(Some("1.0-1"), None),
            SurveyClass::CurrentUnknown
        );
    }

    #[test]
    fn packages_core_same_without_cosmic() {
        let p = packages_for_profile(false);
        assert_eq!(p, CORE_PACKAGES);
        assert!(!p.contains(&COSMIC_EXTRA));
    }

    #[test]
    fn packages_cosmic_adds_only_extra() {
        let p = packages_for_profile(true);
        assert_eq!(p.len(), CORE_PACKAGES.len() + 1);
        assert_eq!(p.last().copied(), Some(COSMIC_EXTRA));
        for c in CORE_PACKAGES {
            assert!(p.contains(c));
        }
    }

    #[test]
    fn plan_blurb_never_implies_generic_gets_less() {
        let g = format_plan_blurb(false);
        let c = format_plan_blurb(true);
        assert!(g.contains("Core stack (all DEs)"));
        assert!(c.contains("Core stack (all DEs)"));
        assert!(c.contains(COSMIC_EXTRA));
        assert!(!g.contains("full saver set"));
        assert!(!g.contains("core package set") || g.contains("Core stack"));
    }

    #[test]
    fn survey_summary_uses_attempt_not_will_raise() {
        let lines = format_survey_summary(2, 1);
        let joined = lines.join("\n");
        assert!(joined.contains("will attempt upgrade"));
        assert!(joined.contains("will attempt install"));
        assert!(!joined.contains("will raise"));
        assert!(!joined.to_lowercase().contains("will install.") || joined.contains("attempt"));
    }

    #[test]
    fn survey_summary_all_current_honest() {
        let lines = format_survey_summary(0, 0);
        assert_eq!(lines.len(), 1);
        assert!(lines[0].contains("look current"));
        assert!(lines[0].contains("re-sync"));
    }

    #[test]
    fn victory_banner_three_truths() {
        assert_eq!(victory_banner(true, true).0, "INSTALL FINISHED");
        assert_eq!(victory_banner(true, false).0, "PACKAGES INSTALLED");
        assert_eq!(victory_banner(false, true).0, "INSTALL PARTIAL");
        assert_eq!(victory_banner(false, false).0, "INSTALL PARTIAL");
    }

    #[test]
    fn victory_box_rows_same_width() {
        for t in ["INSTALL FINISHED", "PACKAGES INSTALLED", "INSTALL PARTIAL"] {
            let box_lines = format_victory_box(t);
            let refs: Vec<&str> = box_lines.iter().map(|s| s.as_str()).collect();
            assert!(
                lines_same_width(&refs),
                "mismatched widths for {t:?}: {:?}",
                box_lines
                    .iter()
                    .map(|s| s.chars().count())
                    .collect::<Vec<_>>()
            );
            let w = box_lines[0].chars().count();
            for line in &box_lines {
                assert_eq!(line.chars().count(), w, "line={line:?}");
            }
        }
    }

    #[test]
    fn victory_title_row_inner_is_fixed() {
        for t in ["INSTALL FINISHED", "PACKAGES INSTALLED", "INSTALL PARTIAL"] {
            let row = format_victory_box_title_row(t);
            assert!(row.starts_with('║') && row.ends_with('║'));
            let inner: String = row.chars().skip(1).take(row.chars().count() - 2).collect();
            assert_eq!(
                inner.chars().count(),
                VICTORY_BOX_INNER,
                "title={t:?} inner={inner:?}"
            );
        }
    }

    #[test]
    fn victory_title_is_centered_not_left_padded_field() {
        // Regression: old code used {title:<20} so "INSTALL FINISHED" left a
        // lopsided gap before the right ornament (looked broken in the TTY).
        let body = format_victory_title_body("INSTALL FINISHED");
        assert_eq!(body.chars().count(), VICTORY_BOX_INNER);
        let trimmed = body.trim();
        assert!(
            trimmed.starts_with(VICTORY_ORNAMENT) && trimmed.ends_with(VICTORY_ORNAMENT),
            "body={body:?}"
        );
        // Leading and trailing pad should be nearly equal (off-by-one ok).
        let lead = body.chars().take_while(|c| *c == ' ').count();
        let trail = body.chars().rev().take_while(|c| *c == ' ').count();
        assert!(
            lead.abs_diff(trail) <= 1,
            "not centered: lead={lead} trail={trail} body={body:?}"
        );
        // Must not look like left-field pad: "INSTALL FINISHED      ✦"
        assert!(
            !body.contains("FINISHED      "),
            "left-aligned 20-col field still present: {body:?}"
        );
    }

    #[test]
    fn center_in_width_basic() {
        assert_eq!(center_in_width("ab", 6), "  ab  ");
        assert_eq!(center_in_width("abc", 6), " abc  ");
        assert_eq!(center_in_width("abcdef", 4), "abcd");
    }

    #[test]
    fn gpg_disclaimer_does_not_claim_repo_signed() {
        assert!(DNF_GPG_DISCLAIMER.contains("gpgcheck=1"));
        assert!(DNF_GPG_DISCLAIMER.contains("repo_gpgcheck=0"));
        assert!(!DNF_GPG_DISCLAIMER.to_lowercase().contains("repo signed"));
    }

    #[test]
    fn deploy_result_honest_partial() {
        let s = format_deploy_result(3, 5);
        assert!(s.contains("3/5"));
        assert!(!s.contains("all 3"));
        let all = format_deploy_result(5, 5);
        assert!(all.contains("all 5"));
    }

    #[test]
    fn cosmic_line_truth_table() {
        assert!(format_cosmic_line(false, false).is_none());
        let inst = format_cosmic_line(true, true).unwrap();
        assert!(inst.contains("is installed"));
        assert!(inst.contains("if not docked"));
        let miss = format_cosmic_line(true, false).unwrap();
        assert!(miss.contains("not installed"));
    }

    #[test]
    fn survey_row_upgrade_shows_both_versions() {
        let r = format_survey_row_plain(
            "idle-daemon",
            SurveyClass::Upgrade,
            Some("2.5.9-1"),
            Some("2.5.10-1"),
        );
        assert!(r.contains("2.5.9-1"));
        assert!(r.contains("2.5.10-1"));
        assert!(r.contains("upgrade"));
    }

    #[test]
    fn survey_row_unknown_channel_does_not_say_matches() {
        let r = format_survey_row_plain(
            "idle-cli",
            SurveyClass::CurrentUnknown,
            Some("2.5.5-1"),
            None,
        );
        assert!(r.contains("channel version unknown"));
        assert!(!r.contains("matches channel"));
    }

    #[test]
    fn strip_ansi_removes_csi() {
        let s = "\x1b[38;5;82m✔\x1b[0m ok";
        assert_eq!(strip_ansi(s), "✔ ok");
    }

    #[test]
    fn lines_same_width_detects_mismatch() {
        assert!(lines_same_width(&["abc", "xyz"]));
        assert!(!lines_same_width(&["abc", "abcd"]));
    }

    /// install.sh must stay aligned with pure honesty helpers (no "will raise", GPG truth, banners).
    #[test]
    fn install_sh_honesty_phrases_aligned() {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("install.sh");
        let s = std::fs::read_to_string(&path).expect("read install.sh");
        assert!(
            s.contains("will attempt upgrade to channel"),
            "survey must say attempt upgrade"
        );
        assert!(
            s.contains("will attempt install"),
            "survey must say attempt install"
        );
        assert!(s.contains("look current"), "all-current survey wording");
        assert!(
            s.contains("package gpgcheck=1") && s.contains("repo_gpgcheck=0"),
            "DNF disclaimer must not overclaim repo signing"
        );
        assert!(
            !s.contains("repo signed"),
            "must not claim repo metadata signed"
        );
        for title in ["INSTALL FINISHED", "PACKAGES INSTALLED", "INSTALL PARTIAL"] {
            assert!(s.contains(title), "victory banner {title}");
        }
        assert!(s.contains("packages present · daemon active"));
        assert!(s.contains("daemon not active yet"));
        assert!(s.contains("some planned packages missing"));
        // Must not promise install success in the survey phase.
        assert!(
            !s.contains("will raise to channel"),
            "survey must not claim raise succeeds"
        );
        // Core plan language
        assert!(s.contains("Core stack (all DEs)"));
        assert!(s.contains("channel version unknown"));
        assert!(s.contains("matches channel"));
    }

    #[test]
    fn install_sh_core_packages_list_matches() {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("install.sh");
        let s = std::fs::read_to_string(&path).expect("read install.sh");
        for pkg in CORE_PACKAGES {
            assert!(
                s.contains(pkg),
                "install.sh must mention core package {pkg}"
            );
        }
        assert!(s.contains(COSMIC_EXTRA));
    }
}
