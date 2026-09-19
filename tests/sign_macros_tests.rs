//! Property tests for GPG identity helpers and rpmmacros generation — std-only.

use idlescreen_packages::{
    build_rpmmacros, gpg_name_is_valid, resolve_gpg_bin, resolve_signing_key,
};

mod common;
use common::{Rng, any_text, gpg_id, maybe_spaces, non_empty_line, safe_macro_field};

const CASES: usize = 512;

/// Non-empty trimmed names are valid; pure whitespace is not.
#[test]
fn prop_gpg_name_valid_iff_nonempty_trim() {
    let mut rng = Rng::new(0x6B1_0001);
    for _ in 0..CASES {
        let core = gpg_id(&mut rng);
        let pad = maybe_spaces(&mut rng);
        let padded = format!("{pad}{core}{pad}");
        assert!(gpg_name_is_valid(&padded));
        assert!(!gpg_name_is_valid(&pad));
    }
}

/// Newlines in identity always invalidate the name.
#[test]
fn prop_gpg_name_rejects_newlines() {
    let mut rng = Rng::new(0x6B1_0002);
    for _ in 0..CASES {
        let left = rng.string(&['a', 'b', 'c', '0', '1', '2'], 0, 12);
        let right = rng.string(&['a', 'b', 'c', '0', '1', '2'], 0, 12);
        let with_lf = format!("{left}\n{right}");
        let with_cr = format!("{left}\r{right}");
        assert!(!gpg_name_is_valid(&with_lf));
        assert!(!gpg_name_is_valid(&with_cr));
    }
}

/// Macros always embed name and bin; path line only when provided.
#[test]
fn prop_macros_contain_fields() {
    let mut rng = Rng::new(0x6B1_0003);
    for _ in 0..CASES {
        let name = safe_macro_field(&mut rng);
        let bin = safe_macro_field(&mut rng);
        let path = rng.opt(|r| safe_macro_field(r));
        let content = build_rpmmacros(&name, &bin, path.as_deref());
        assert!(content.contains("%_signature gpg\n"));
        let name_line = format!("%_gpg_name {name}\n");
        let bin_line = format!("%_gpgbin {bin}\n");
        assert!(content.contains(&name_line), "missing name line");
        assert!(content.contains(&bin_line), "missing bin line");
        match &path {
            Some(p) => {
                let line = format!("%_gpg_path {p}\n");
                assert!(content.contains(&line));
            }
            None => {
                assert!(!content.contains("%_gpg_path"));
            }
        }
        // Exactly one line per macro key — no injection.
        assert_eq!(content.matches("%_gpg_name ").count(), 1);
        assert_eq!(content.matches("%_gpgbin ").count(), 1);
    }
}

/// resolve_signing_key prefers non-empty env over default.
#[test]
fn prop_resolve_signing_key() {
    let mut rng = Rng::new(0x6B1_0004);
    for _ in 0..CASES {
        let env = rng.opt(|r| non_empty_line(r));
        let default = non_empty_line(&mut rng);
        let got = resolve_signing_key(env.as_deref(), &default);
        match &env {
            Some(v) if gpg_name_is_valid(v) => assert_eq!(&got, v),
            _ => assert_eq!(got, default),
        }
    }
}

/// resolve_gpg_bin defaults to "gpg" when missing, empty, or unsafe.
#[test]
fn prop_resolve_gpg_bin() {
    let mut rng = Rng::new(0x6B1_0005);
    for _ in 0..CASES {
        let env = rng.opt(|r| any_text(r, 20));
        let got = resolve_gpg_bin(env.as_deref());
        match &env {
            Some(v) if !v.is_empty() && !v.contains('\n') && !v.contains('\r') => {
                assert_eq!(&got, v);
            }
            _ => assert_eq!(got, "gpg"),
        }
    }
}

/// Macros end with a trailing newline (file-friendly).
#[test]
fn prop_macros_trailing_newline() {
    let mut rng = Rng::new(0x6B1_0006);
    for _ in 0..CASES {
        let name = safe_macro_field(&mut rng);
        let bin = safe_macro_field(&mut rng);
        let with_path = rng.boolean();
        let path = if with_path { Some("/tmp/gnupg") } else { None };
        let content = build_rpmmacros(&name, &bin, path);
        assert!(content.ends_with('\n'));
    }
}
