// SPDX-License-Identifier: Apache-2.0

use crate::compare_versions;
use std::cmp::Ordering;
use super::constants::{CORE_PACKAGES, COSMIC_EXTRA};

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
}
