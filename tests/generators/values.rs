// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 IdleScreen

//! Value and token generators for test fixtures.

#![allow(dead_code)]

use super::rng::Rng;

const ALNUM: &[char] = &[
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i',
    'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', 'A', 'B',
    'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U',
    'V', 'W', 'X', 'Y', 'Z',
];
const LOWER_DIGIT: &[char] = &[
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's',
    't', 'u', 'v', 'w', 'x', 'y', 'z', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
];
const DIGITS: &[char] = &['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
const LOWER: &[char] = &[
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's',
    't', 'u', 'v', 'w', 'x', 'y', 'z',
];
const SAFE_SEG: &[char] = &[
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S',
    'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l',
    'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '0', '1', '2', '3', '4',
    '5', '6', '7', '8', '9', '.', '_', '+', '-',
];
const MACRO_FIELD: &[char] = &[
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S',
    'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l',
    'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '0', '1', '2', '3', '4',
    '5', '6', '7', '8', '9', '@', '.', '_', '+', '/', '\\', '-',
];
const WS: &[char] = &[' ', '\t'];

/// `[0-9A-Za-z]{1,8}` — version_token()
pub fn version_token(rng: &mut Rng) -> String {
    rng.string(ALNUM, 1, 8)
}

/// `version_token().join(".")` with 1..=5 parts — version_string()
pub fn version_string(rng: &mut Rng) -> String {
    let n = rng.range(1, 5) as usize;
    (0..n)
        .map(|_| version_token(rng))
        .collect::<Vec<_>>()
        .join(".")
}

/// `X.Y.Z` with each field in `0..limit` — semver_core()
pub fn semver_core(rng: &mut Rng, limit: u64) -> String {
    format!(
        "{}.{}.{}",
        rng.below(limit),
        rng.below(limit),
        rng.below(limit)
    )
}

/// `[a-z][a-z0-9]{0,max}` — pkg_name()
pub fn pkg_name(rng: &mut Rng, max: usize) -> String {
    let mut s = String::from(LOWER[rng.below(26) as usize]);
    s.push_str(&rng.string(LOWER_DIGIT, 0, max));
    s
}

/// `[0-9]+(\.[0-9]+){0,3}` — version_seg()
pub fn version_seg(rng: &mut Rng) -> String {
    let mut s = rng.string(DIGITS, 1, 4);
    for _ in 0..rng.below(4) {
        s.push('.');
        s.push_str(&rng.string(DIGITS, 1, 4));
    }
    s
}

/// `[0-9]{1,3}` — rpm release field
pub fn rel_num(rng: &mut Rng, max: usize) -> String {
    rng.string(DIGITS, 1, max)
}

/// deb arch
pub fn arch_deb(rng: &mut Rng) -> &'static str {
    ["amd64", "all"][rng.below(2) as usize]
}

/// rpm arch
pub fn arch_rpm(rng: &mut Rng) -> &'static str {
    ["x86_64", "noarch", "aarch64"][rng.below(3) as usize]
}

/// `[A-Za-z0-9][A-Za-z0-9._+-]{0,24}` — safe_segment()
pub fn safe_segment(rng: &mut Rng) -> String {
    let mut s = String::from(ALNUM[rng.below(ALNUM.len() as u64) as usize]);
    s.push_str(&rng.string(SAFE_SEG, 0, 24));
    s
}

/// Arbitrary printable-and-control text up to `max` chars — `.*{0,max}`
pub fn any_text(rng: &mut Rng, max: usize) -> String {
    let len = rng.below(max as u64 + 1) as usize;
    (0..len)
        .map(|_| {
            // Mostly printable ASCII with occasional control chars.
            let b = if rng.below(16) == 0 {
                rng.below(32) as u8
            } else {
                32 + rng.below(95) as u8
            };
            b as char
        })
        .collect()
}

/// `[A-Za-z0-9@._+/-]{1,40}` — safe_macro_field()
pub fn safe_macro_field(rng: &mut Rng) -> String {
    rng.string(MACRO_FIELD, 1, 40)
}

/// `[A-Za-z0-9@._+-]{1,24}` — gpg name core
pub fn gpg_id(rng: &mut Rng) -> String {
    rng.string(MACRO_FIELD, 1, 24)
}

/// `[ \t]{0,8}` — maybe_spaces()
pub fn maybe_spaces(rng: &mut Rng) -> String {
    rng.string(WS, 0, 8)
}

/// Non-newline text `{1,40}` — non_empty_line()
pub fn non_empty_line(rng: &mut Rng) -> String {
    let len = rng.range(1, 40) as usize;
    (0..len)
        .map(|_| {
            loop {
                let b = rng.below(128) as u8;
                if b != b'\n' && b != b'\r' {
                    break b as char;
                }
            }
        })
        .collect()
}
