//! Version string comparison for package prune ordering.
// SPDX-License-Identifier: Apache-2.0

use std::cmp::Ordering;

/// Minimal strict semver 2.0 (`MAJOR.MINOR.PATCH[-pre][+build]`).
///
/// Ordering follows semver precedence: numeric identifiers sort before
/// alphanumeric, a release sorts after any of its prereleases, and build
/// metadata is ignored. Replaces the `semver` crate for the narrow
/// parse-and-compare use here.
#[derive(Clone, Debug, Eq, PartialEq)]
struct Semver {
    major: u64,
    minor: u64,
    patch: u64,
    pre: Vec<PreId>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum PreId {
    Num(u64),
    Alpha(String),
}

impl Semver {
    fn parse(s: &str) -> Option<Self> {
        let (head, build) = match s.split_once('+') {
            Some((h, b)) => (h, Some(b)),
            None => (s, None),
        };
        if let Some(b) = build {
            if !b.split('.').all(|i| is_ident(i)) {
                return None;
            }
        }
        let (core, pre) = match head.split_once('-') {
            Some((c, p)) => (c, Some(p)),
            None => (head, None),
        };
        let mut parts = core.split('.');
        let major = parse_num(parts.next()?)?;
        let minor = parse_num(parts.next()?)?;
        let patch = parse_num(parts.next()?)?;
        if parts.next().is_some() {
            return None;
        }
        let pre = match pre {
            Some(p) => p
                .split('.')
                .map(|i| {
                    if !is_ident(i) {
                        return None;
                    }
                    if i.bytes().all(|b| b.is_ascii_digit()) {
                        Some(PreId::Num(parse_num(i)?))
                    } else {
                        Some(PreId::Alpha(i.to_string()))
                    }
                })
                .collect::<Option<Vec<_>>>()?,
            None => Vec::new(),
        };
        Some(Self {
            major,
            minor,
            patch,
            pre,
        })
    }
}

/// Identifier char set shared by prerelease and build: `[0-9A-Za-z-]`, non-empty.
fn is_ident(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
}

/// Strict numeric field: digits only, no leading zeros, fits in u64.
fn parse_num(s: &str) -> Option<u64> {
    if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    if s.len() > 1 && s.starts_with('0') {
        return None;
    }
    s.parse().ok()
}

impl Ord for Semver {
    fn cmp(&self, other: &Self) -> Ordering {
        (self.major, self.minor, self.patch)
            .cmp(&(other.major, other.minor, other.patch))
            .then_with(|| match (self.pre.is_empty(), other.pre.is_empty()) {
                (true, true) => Ordering::Equal,
                (true, false) => Ordering::Greater,
                (false, true) => Ordering::Less,
                (false, false) => cmp_pre(&self.pre, &other.pre),
            })
    }
}

impl PartialOrd for Semver {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

fn cmp_pre(a: &[PreId], b: &[PreId]) -> Ordering {
    for (x, y) in a.iter().zip(b.iter()) {
        let ord = match (x, y) {
            (PreId::Num(x), PreId::Num(y)) => x.cmp(y),
            (PreId::Num(_), PreId::Alpha(_)) => Ordering::Less,
            (PreId::Alpha(_), PreId::Num(_)) => Ordering::Greater,
            (PreId::Alpha(x), PreId::Alpha(y)) => x.cmp(y),
        };
        if ord != Ordering::Equal {
            return ord;
        }
    }
    a.len().cmp(&b.len())
}

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
    if let (Some(av), Some(bv)) = (Semver::parse(a), Semver::parse(b)) {
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

    #[test]
    fn malformed_version_strings_never_panic() {
        for v in [
            "", ".", "..", "1", "1.", ".1", "1.2.3.4", "-1.0.0", "v1.0.0",
            "1.0.0-", "1.0.0+", "1.0.0-alpha..1", "1.0.0--", "01.0.0", "1.02.3",
            "1.2.3-0", "18446744073709551616.0.0", "99999999999999999999999999.0.0",
            "a.b.c", "1.0.0-alpha.1.2.3.4.5", "\u{1F600}", "1.0.0-rc.1+build.5",
            "x", "0.0.0", "10.20.30", "1.0.0-beta+exp.sha.5114f85", "3.2.4-1",
        ] {
            let _ = Semver::parse(v);
            let _ = compare_versions(v, "1.0.0");
            let _ = compare_versions("1.0.0", v);
            let _ = compare_versions(v, v);
            let _ = split_parts(v);
        }
    }
}
