// SPDX-License-Identifier: Apache-2.0

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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::install_honesty::format::lines_same_width;

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
}
