//! Property tests for GPG identity helpers and rpmmacros generation.
// SPDX-License-Identifier: Apache-2.0

use crateria_packages::{
    build_rpmmacros, gpg_name_is_valid, resolve_gpg_bin, resolve_signing_key,
};
use proptest::prelude::*;

fn non_empty_line() -> impl Strategy<Value = String> {
    // Avoid newlines so macro file lines stay single-line (as callers should).
    prop::string::string_regex("[^\\n\\r]{1,40}").expect("line")
}

fn maybe_spaces() -> impl Strategy<Value = String> {
    prop::string::string_regex("[ \\t]{0,8}").expect("ws")
}

proptest! {
    /// Non-empty trimmed names are valid; pure whitespace is not.
    #[test]
    fn prop_gpg_name_valid_iff_nonempty_trim(
        core in prop::string::string_regex("[A-Za-z0-9@._+-]{1,24}").expect("id"),
        pad in maybe_spaces(),
    ) {
        let padded = format!("{pad}{core}{pad}");
        prop_assert!(gpg_name_is_valid(&padded));
        prop_assert!(!gpg_name_is_valid(&pad));
    }
}

proptest! {
    /// Macros always embed name and bin; path line only when provided.
    #[test]
    fn prop_macros_contain_fields(
        name in non_empty_line(),
        bin in non_empty_line(),
        path in prop::option::of(non_empty_line()),
    ) {
        let content = build_rpmmacros(&name, &bin, path.as_deref());
        prop_assert!(content.contains("%_signature gpg\n"));
        let name_line = format!("%_gpg_name {name}\n");
        let bin_line = format!("%_gpgbin {bin}\n");
        prop_assert!(content.contains(&name_line), "missing name line");
        prop_assert!(content.contains(&bin_line), "missing bin line");
        match &path {
            Some(p) => {
                let line = format!("%_gpg_path {p}\n");
                prop_assert!(content.contains(&line));
            }
            None => {
                prop_assert!(!content.contains("%_gpg_path"));
            }
        }
    }
}

proptest! {
    /// resolve_signing_key prefers non-empty env over default.
    #[test]
    fn prop_resolve_signing_key(
        env in prop::option::of(non_empty_line()),
        default in non_empty_line(),
    ) {
        let got = resolve_signing_key(env.as_deref(), &default);
        match &env {
            Some(v) if gpg_name_is_valid(v) => prop_assert_eq!(&got, v),
            _ => prop_assert_eq!(got, default),
        }
    }
}

proptest! {
    /// resolve_gpg_bin defaults to "gpg" when missing or empty.
    #[test]
    fn prop_resolve_gpg_bin(env in prop::option::of(".*{0,20}")) {
        let got = resolve_gpg_bin(env.as_deref());
        match &env {
            Some(v) if !v.is_empty() => prop_assert_eq!(&got, v),
            _ => prop_assert_eq!(got, "gpg"),
        }
    }
}

proptest! {
    /// Macros end with a trailing newline (file-friendly).
    #[test]
    fn prop_macros_trailing_newline(
        name in non_empty_line(),
        bin in non_empty_line(),
        with_path in any::<bool>(),
    ) {
        let path = if with_path { Some("/tmp/gnupg") } else { None };
        let content = build_rpmmacros(&name, &bin, path);
        prop_assert!(content.ends_with('\n'));
    }
}
