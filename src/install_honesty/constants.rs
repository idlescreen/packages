// SPDX-License-Identifier: Apache-2.0

/// Core packages always requested (every DE).
pub const CORE_PACKAGES: &[&str] = &[
    "idle-daemon",
    "idle-cli",
    "idle-savers",
    "idle-tui",
    "idlescreen",
];

/// Extra package only when COSMIC is detected.
pub const COSMIC_EXTRA: &str = "idle-cosmic";

/// Official saver plugins pulled by `idle-savers` (and wiped when idlescreen is removed).
pub const OFFICIAL_SAVERS: &[&str] = &[
    "idle-saver-beams",
    "idle-saver-bursts",
    "idle-saver-chaos",
    "idle-saver-cosmos",
    "idle-saver-glyphs",
    "idle-saver-gnats",
    "idle-saver-hearth",
    "idle-saver-radar",
    "idle-saver-ripple",
    "idle-saver-storm",
];

/// Full product stack erased by `dnf/apt remove idlescreen` (idlescreen 2.6+).
/// Does not include `idlescreen` itself (already being removed) or user config.
pub const PRODUCT_STACK_ON_REMOVE: &[&str] = &[
    "idle-cosmic",
    "idle-tui",
    "idle-cli",
    "idle-savers",
    "idle-saver-beams",
    "idle-saver-bursts",
    "idle-saver-chaos",
    "idle-saver-cosmos",
    "idle-saver-glyphs",
    "idle-saver-gnats",
    "idle-saver-hearth",
    "idle-saver-radar",
    "idle-saver-ripple",
    "idle-saver-storm",
    "idle-daemon",
];

/// Honest one-liner for uninstall docs / victory footer.
pub const REMOVE_BLURB: &str =
    "sudo dnf remove idlescreen   # also removes modules, savers, idle-cosmic, repo drop-in";

/// Truthful DNF channel disclaimer (packages GPG-checked; repo metadata not).
pub const DNF_GPG_DISCLAIMER: &str = "package gpgcheck=1 · repo_gpgcheck=0";

#[cfg(test)]
mod tests {
    use super::*;

    /// Helper to load full installer content across decomposed installer scripts.
    fn load_installer_scripts() -> String {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
        let scripts = [
            "install.sh",
            "install_core.sh",
            "repo.sh",
            "post_install.sh",
            "ui.sh",
            "detect.sh",
        ];
        let mut combined = String::new();
        for name in scripts {
            let path = dir.join(name);
            if path.exists() {
                let content = std::fs::read_to_string(&path)
                    .unwrap_or_else(|_| panic!("read {name}"));
                combined.push_str(&content);
                combined.push('\n');
            }
        }
        combined
    }

    /// install.sh (and its sourced scripts) must stay aligned with pure honesty helpers (no "will raise", GPG truth, banners).
    #[test]
    fn install_sh_honesty_phrases_aligned() {
        let s = load_installer_scripts();
        assert!(
            s.contains("will attempt upgrade to channel"),
            "survey must say attempt upgrade"
        );
        assert!(
            s.contains("will attempt install"),
            "survey must say attempt install"
        );
        assert!(s.contains("look current"), "all-current survey wording");
        assert!(
            s.contains("package gpgcheck=1") && s.contains("repo_gpgcheck=0"),
            "DNF disclaimer must not overclaim repo signing"
        );
        assert!(
            !s.contains("repo signed"),
            "must not claim repo metadata signed"
        );
        for title in ["INSTALL FINISHED", "PACKAGES INSTALLED", "INSTALL PARTIAL"] {
            assert!(s.contains(title), "victory banner {title}");
        }
        assert!(s.contains("packages present · daemon active"));
        assert!(s.contains("daemon not active yet"));
        assert!(s.contains("some planned packages missing"));
        // Must not promise install success in the survey phase.
        assert!(
            !s.contains("will raise to channel"),
            "survey must not claim raise succeeds"
        );
        // Core plan language
        assert!(s.contains("Core stack (all DEs)"));
        assert!(s.contains("channel version unknown"));
        assert!(s.contains("matches channel"));
    }

    #[test]
    fn install_sh_core_packages_list_matches() {
        let s = load_installer_scripts();
        for pkg in CORE_PACKAGES {
            assert!(
                s.contains(pkg),
                "install.sh must mention core package {pkg}"
            );
        }
        assert!(s.contains(COSMIC_EXTRA));
    }

    #[test]
    fn product_stack_on_remove_covers_installer_and_savers() {
        for p in [
            "idle-daemon",
            "idle-cli",
            "idle-savers",
            "idle-tui",
            "idle-cosmic",
        ] {
            assert!(
                PRODUCT_STACK_ON_REMOVE.contains(&p),
                "missing module {p} from remove list"
            );
        }
        for s in OFFICIAL_SAVERS {
            assert!(
                PRODUCT_STACK_ON_REMOVE.contains(s),
                "missing saver {s} from remove list"
            );
        }
        // Brand package is removed by the package manager itself, not the scriptlet list.
        assert!(!PRODUCT_STACK_ON_REMOVE.contains(&"idlescreen"));
    }

    #[test]
    fn remove_product_stack_sh_lists_match_const() {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("metapackages/idlescreen/remove-product-stack.sh");
        let s = std::fs::read_to_string(&path).expect("read remove-product-stack.sh");
        for p in PRODUCT_STACK_ON_REMOVE {
            assert!(s.contains(p), "remove-product-stack.sh must list {p}");
        }
        assert!(s.contains("idlescreen.repo"));
        assert!(s.contains("idlescreen.list"));
    }

    #[test]
    fn remove_blurb_documents_stack_wipe() {
        assert!(REMOVE_BLURB.contains("dnf remove idlescreen"));
        assert!(REMOVE_BLURB.contains("modules") || REMOVE_BLURB.contains("savers"));
    }
}
