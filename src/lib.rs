//! Shared library for crateria package repository maintenance tools.
//!
//! Pure helpers for version ordering, package filename parsing, prune
//! selection, pool path construction, and signing macro generation.

// SPDX-License-Identifier: Apache-2.0

pub mod package_parse;
pub mod paths;
pub mod prune_core;
pub mod sign_macros;
pub mod sweep;
pub mod version_cmp;

pub use package_parse::{parse_deb_filename, parse_rpm_filename, PackageId};
pub use paths::{
    deb_pool_dest, is_rpm_path, is_under_base, package_sweep_dest, rpm_pool_dest, safe_join_under,
};
pub use prune_core::{group_by_name, select_to_remove, PackageFile};
pub use sign_macros::{
    build_rpmmacros, gpg_name_is_valid, resolve_gpg_bin, resolve_signing_key,
};
pub use sweep::sweep_loose_packages;
pub use version_cmp::{compare_versions, split_parts};
