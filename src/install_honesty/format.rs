// SPDX-License-Identifier: Apache-2.0

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

#[cfg(test)]
mod tests {
    use super::super::constants::DNF_GPG_DISCLAIMER;
    use super::*;

    #[test]
    fn gpg_disclaimer_accurately_states_signing() {
        assert!(DNF_GPG_DISCLAIMER.contains("gpgcheck=1"));
        assert!(DNF_GPG_DISCLAIMER.contains("repo_gpgcheck=1"));
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
    fn strip_ansi_removes_csi() {
        let s = "\x1b[38;5;82m✔\x1b[0m ok";
        assert_eq!(strip_ansi(s), "✔ ok");
    }

    #[test]
    fn lines_same_width_detects_mismatch() {
        assert!(lines_same_width(&["abc", "xyz"]));
        assert!(!lines_same_width(&["abc", "abcd"]));
    }
}
