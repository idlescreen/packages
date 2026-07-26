//! Shared library for IdleScreen package repository maintenance tools.
//!
//! Crate/lib: `idlescreen-packages` / `idlescreen_packages`. Product brand and
//! host: IdleScreen (`idlescreen.github.io`). Pure helpers for version ordering,
//! package filename parsing, prune selection, pool path construction, and
//! signing macro generation.
//!
//! GPG env vars: prefer `IDLESCREEN_GPG_*`; legacy `CRATERIA_GPG_*` still accepted.

// SPDX-License-Identifier: Apache-2.0

pub mod install_honesty;
pub mod package_parse;
pub mod paths;
pub mod prune_core;
pub mod sign_macros;
pub mod sweep;
pub mod version_cmp;

pub use install_honesty::{
    CORE_PACKAGES, COSMIC_EXTRA, DNF_GPG_DISCLAIMER, SurveyClass, VICTORY_BOX_INNER,
    VICTORY_ORNAMENT, center_in_width, classify_package, format_cosmic_line, format_deploy_result,
    format_plan_blurb, format_survey_row_plain, format_survey_summary, format_victory_box,
    format_victory_box_title_row, format_victory_title_body, lines_same_width,
    packages_for_profile, strip_ansi, version_is_older, victory_banner,
    victory_box_border_inner_width,
};
pub use package_parse::{PackageId, parse_deb_filename, parse_rpm_filename};
pub use paths::{
    deb_pool_dest, is_rpm_path, is_under_base, package_sweep_dest, rpm_pool_dest, safe_join_under,
};
pub use prune_core::{PackageFile, group_by_name, select_to_remove};
pub use sign_macros::{build_rpmmacros, gpg_name_is_valid, resolve_gpg_bin, resolve_signing_key};
pub use sweep::sweep_loose_packages;
pub use version_cmp::{compare_versions, split_parts};
