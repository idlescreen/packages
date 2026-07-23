//! Shared library for IdleScreen package repository maintenance tools.
//!
//! Crate name remains `crateria_packages` for Cargo/API stability; product
//! brand is IdleScreen (idlescreen.github.io). Pure helpers for version
//! ordering, package filename parsing, prune selection, pool path
//! construction, and signing macro generation.

// SPDX-License-Identifier: Apache-2.0

pub mod package_parse;
pub mod paths;
pub mod prune_core;
pub mod sign_macros;
pub mod sweep;
pub mod version_cmp;

pub use package_parse::{PackageId, parse_deb_filename, parse_rpm_filename};
pub use paths::{
    deb_pool_dest, is_rpm_path, is_under_base, package_sweep_dest, rpm_pool_dest, safe_join_under,
};
pub use prune_core::{PackageFile, group_by_name, select_to_remove};
pub use sign_macros::{build_rpmmacros, gpg_name_is_valid, resolve_gpg_bin, resolve_signing_key};
pub use sweep::sweep_loose_packages;
pub use version_cmp::{compare_versions, split_parts};
