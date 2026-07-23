//! Property tests for version splitting and comparison.
// SPDX-License-Identifier: Apache-2.0

use crateria_packages::{compare_versions, split_parts};
use proptest::prelude::*;
use std::cmp::Ordering;

/// Alphanumeric version-ish tokens (no empty).
fn version_token() -> impl Strategy<Value = String> {
    prop::string::string_regex("[0-9A-Za-z]{1,8}").expect("token regex")
}

fn version_string() -> impl Strategy<Value = String> {
    prop::collection::vec(version_token(), 1..6).prop_map(|parts| parts.join("."))
}

/// Strict semver core: MAJOR.MINOR.PATCH (numeric, no leading junk).
fn semver_core() -> impl Strategy<Value = String> {
    (0u64..50, 0u64..50, 0u64..50).prop_map(|(a, b, c)| format!("{a}.{b}.{c}"))
}

proptest! {
    /// `compare_versions(x, x)` is always Equal.
    #[test]
    fn prop_compare_reflexive(v in ".*{0,40}") {
        prop_assert_eq!(compare_versions(&v, &v), Ordering::Equal);
    }
}

proptest! {
    /// Antisymmetry: cmp(a,b) == reverse(cmp(b,a)).
    #[test]
    fn prop_compare_antisymmetry(a in version_string(), b in version_string()) {
        prop_assert_eq!(
            compare_versions(&a, &b),
            compare_versions(&b, &a).reverse()
        );
    }
}

proptest! {
    /// When both sides are valid semver, ordering matches `semver::Version`.
    #[test]
    fn prop_semver_consistent(a in semver_core(), b in semver_core()) {
        let av = semver::Version::parse(&a).expect("a semver");
        let bv = semver::Version::parse(&b).expect("b semver");
        prop_assert_eq!(compare_versions(&a, &b), av.cmp(&bv));
    }
}

proptest! {
    /// split_parts only emits non-empty alphanumeric runs.
    #[test]
    fn prop_split_parts_alphanumeric(s in ".*{0,60}") {
        for part in split_parts(&s) {
            prop_assert!(!part.is_empty());
            prop_assert!(part.chars().all(|c| c.is_alphanumeric()));
        }
    }
}

proptest! {
    /// Joining split parts with a separator and re-splitting is stable for pure tokens.
    #[test]
    fn prop_split_roundtrip_tokens(parts in prop::collection::vec(version_token(), 1..6)) {
        let joined = parts.join(".");
        let again = split_parts(&joined);
        prop_assert_eq!(again, parts);
    }
}

proptest! {
    /// Total order on a triple: at most one of <, >, = between each pair direction.
    #[test]
    fn prop_compare_trichotomy(a in version_string(), b in version_string()) {
        let ab = compare_versions(&a, &b);
        let ba = compare_versions(&b, &a);
        match ab {
            Ordering::Equal => prop_assert_eq!(ba, Ordering::Equal),
            Ordering::Less => prop_assert_eq!(ba, Ordering::Greater),
            Ordering::Greater => prop_assert_eq!(ba, Ordering::Less),
        }
    }
}
