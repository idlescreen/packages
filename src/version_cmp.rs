//! Version string comparison for package prune ordering.
// SPDX-License-Identifier: Apache-2.0

use std::cmp::Ordering;

/// Split a version-like string into alphanumeric runs (digits or letters).
///
/// Non-alphanumeric separators are discarded. Empty input yields an empty list.
pub fn split_parts(s: &str) -> Vec<String> {
    let mut parts = Vec::new();
    let mut current = String::new();
    for c in s.chars() {
        if c.is_alphanumeric() {
            current.push(c);
        } else if !current.is_empty() {
            parts.push(std::mem::take(&mut current));
        }
    }
    if !current.is_empty() {
        parts.push(current);
    }
    parts
}

/// Compare package version strings.
///
/// Prefer semver when both sides parse; otherwise compare alphanumeric parts
/// numerically when both are numbers, else lexicographically. Longer part
/// lists sort higher when a common prefix is equal.
pub fn compare_versions(a: &str, b: &str) -> Ordering {
    if let (Ok(av), Ok(bv)) = (semver::Version::parse(a), semver::Version::parse(b)) {
        return av.cmp(&bv);
    }

    let a_parts = split_parts(a);
    let b_parts = split_parts(b);
    for (ap, bp) in a_parts.iter().zip(b_parts.iter()) {
        match (ap.parse::<u64>(), bp.parse::<u64>()) {
            (Ok(an), Ok(bn)) => {
                if an != bn {
                    return an.cmp(&bn);
                }
            }
            _ => {
                if ap != bp {
                    return ap.cmp(bp);
                }
            }
        }
    }
    a_parts.len().cmp(&b_parts.len())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cmp::Ordering;

    #[test]
    fn split_parts_empty() {
        assert!(split_parts("").is_empty());
    }

    #[test]
    fn split_parts_simple() {
        assert_eq!(split_parts("1.2.3"), vec!["1", "2", "3"]);
        assert_eq!(split_parts("1.2.3-1"), vec!["1", "2", "3", "1"]);
    }

    #[test]
    fn split_parts_alphanumeric_runs() {
        assert_eq!(split_parts("1.0rc1"), vec!["1", "0rc1"]);
        assert_eq!(split_parts("---"), Vec::<String>::new());
    }

    #[test]
    fn compare_semver_orders() {
        assert_eq!(compare_versions("1.0.0", "1.0.1"), Ordering::Less);
        assert_eq!(compare_versions("2.0.0", "1.9.9"), Ordering::Greater);
        assert_eq!(compare_versions("1.2.3", "1.2.3"), Ordering::Equal);
    }

    #[test]
    fn compare_fallback_numeric_parts() {
        assert_eq!(compare_versions("1.10", "1.2"), Ordering::Greater);
        assert_eq!(compare_versions("0.3.8", "0.3.56"), Ordering::Less);
    }

    #[test]
    fn compare_equal_is_reflexive() {
        for v in ["1.0.0", "0.3.56-1", "abc", ""] {
            assert_eq!(compare_versions(v, v), Ordering::Equal);
        }
    }

    #[test]
    fn compare_antisymmetry() {
        let pairs = [("1.0.0", "2.0.0"), ("1.2", "1.10"), ("a", "b")];
        for (a, b) in pairs {
            assert_eq!(compare_versions(a, b), compare_versions(b, a).reverse());
        }
    }
}
