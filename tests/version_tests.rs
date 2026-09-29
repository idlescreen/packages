//! Property tests for version splitting and comparison (std-only, deterministic).

use idlescreen_packages::{compare_versions, split_parts};
use std::cmp::Ordering;

mod common;
use common::{Rng, any_text, version_string, version_token};

const CASES: usize = 512;

/// `compare_versions(x, x)` is always Equal.
#[test]
fn prop_compare_reflexive() {
    let mut rng = Rng::new(0xC0DE_0001);
    for _ in 0..CASES {
        let v = any_text(&mut rng, 40);
        assert_eq!(compare_versions(&v, &v), Ordering::Equal);
    }
}

/// Antisymmetry: cmp(a,b) == reverse(cmp(b,a)).
#[test]
fn prop_compare_antisymmetry() {
    let mut rng = Rng::new(0xC0DE_0002);
    for _ in 0..CASES {
        let a = version_string(&mut rng);
        let b = version_string(&mut rng);
        assert_eq!(compare_versions(&a, &b), compare_versions(&b, &a).reverse());
    }
}

/// When both sides are strict `X.Y.Z` semver, ordering matches the numeric
/// triple ordering (the property the `semver` crate previously oracle-tested).
#[test]
fn prop_semver_consistent() {
    let mut rng = Rng::new(0xC0DE_0003);
    for _ in 0..CASES {
        let (a_t, b_t) = (
            (rng.below(50), rng.below(50), rng.below(50)),
            (rng.below(50), rng.below(50), rng.below(50)),
        );
        let a = format!("{}.{}.{}", a_t.0, a_t.1, a_t.2);
        let b = format!("{}.{}.{}", b_t.0, b_t.1, b_t.2);
        assert_eq!(compare_versions(&a, &b), a_t.cmp(&b_t));
    }
}

/// split_parts only emits non-empty alphanumeric runs.
#[test]
fn prop_split_parts_alphanumeric() {
    let mut rng = Rng::new(0xC0DE_0004);
    for _ in 0..CASES {
        let s = any_text(&mut rng, 60);
        for part in split_parts(&s) {
            assert!(!part.is_empty());
            assert!(part.chars().all(|c| c.is_alphanumeric()));
        }
    }
}

/// Joining split parts with a separator and re-splitting is stable for pure tokens.
#[test]
fn prop_split_roundtrip_tokens() {
    let mut rng = Rng::new(0xC0DE_0005);
    for _ in 0..CASES {
        let n = rng.range(1, 5) as usize;
        let parts: Vec<String> = (0..n).map(|_| version_token(&mut rng)).collect();
        let joined = parts.join(".");
        assert_eq!(split_parts(&joined), parts);
    }
}

/// Total order on a pair: antisymmetric directions agree.
#[test]
fn prop_compare_trichotomy() {
    let mut rng = Rng::new(0xC0DE_0006);
    for _ in 0..CASES {
        let a = version_string(&mut rng);
        let b = version_string(&mut rng);
        let ab = compare_versions(&a, &b);
        let ba = compare_versions(&b, &a);
        match ab {
            Ordering::Equal => assert_eq!(ba, Ordering::Equal),
            Ordering::Less => assert_eq!(ba, Ordering::Greater),
            Ordering::Greater => assert_eq!(ba, Ordering::Less),
        }
    }
}
