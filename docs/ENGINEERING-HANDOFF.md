# IdleScreen Engineering Handoff Notes

**Date**: 2026-10-08  
**Author**: Engineering Investigation Team  
**Scope**: GNOME Wayland Compatibility, RPM Packaging, Installer Integrity, and Saver Plugins  
**Target Repositories**: `idlescreen/packages`, `idlescreen/runtime`, `idlescreen/savers`

---

## 1. Executive Summary

During initial testing on a clean Fedora 44 Workstation install (GNOME 50 on Wayland), several interrelated issues were identified across installation, packaging metadata, configuration generation, and runtime daemon startup. 

This document details the exact root causes, code locations, and technical fixes for development on the build server.

---

## 2. Issue 1: Multi-Key GPG Bundle in RPM Repository

### Root Cause
In `idlescreen/packages`, the file `rpm/idlescreen-key.gpg` contains three concatenated OpenPGP public key blocks:
1. `ed25519` key `3D2D670DBD9BD94D7B2D23D356ED99E8C0243160` (Created: 2026-07-05)
2. `rsa3072` key `549E73C9BC9229C786E538E2FBD8FC52C7817DD2` (Created: 2026-07-07)
3. `ed25519` key `CD177C9022D4E3A7085C325952B0A34ACE5AE30D` (Created: 2026-09-30)

When `sudo rpm --import idlescreen-key.gpg` is executed, RPM imports each key block sequentially into the RPM DB, causing user confusion over why multiple keys are being imported.

### Fix
* Export only the primary active signing key into `rpm/idlescreen-key.gpg`.
* If subkeys or rotating keys are maintained, document key transitions or isolate revoked/legacy keys into a designated `rpm/legacy-keys/` directory.

---

## 3. Issue 2: `idle-cosmic` Weak Dependency on Non-COSMIC Desktops (GNOME)

### Root Cause
In `idlescreen/packages`, the `idlescreen` metapackage RPM spec defines:
```spec
Recommends: idle-cosmic
```
On Fedora, DNF has `install_weak_deps=True` by default. When a user runs `sudo dnf install idlescreen` on GNOME Workstation, DNF installs `idle-cosmic` (a ~30MB package intended for COSMIC desktop environments) as an unneeded weak dependency.

### Fix
Replace the flat `Recommends: idle-cosmic` with an RPM rich (boolean) dependency:
```spec
Supplements: (idle-daemon and cosmic-session)
```
Or declare `idle-cosmic` only in an environment-specific subpackage/group. This ensures DNF only pulls the COSMIC applet if `cosmic-session` is present on the host.

---

## 4. Default Screensaver Resolution (`ascii` & `glyphs`)

### Architecture
1. In the IdleScreen codebase (`idlescreen/savers`), the 13 official screensavers are:
   `ascii`, `aurora`, `beams`, `bursts`, `chaos`, `cosmos`, `glyphs`, `gnats`, `hearth`, `radar`, `ripple`, `storm`, and `wasm-demo`.
2. **`ascii`** is the organization-wide default screensaver, featuring 37 randomized text effects dynamically alternating between Host OS, Desktop Environment, and Linux Kernel version with smooth crossfade/dissolve transitions.
3. The falling matrix / digital rain screensaver is officially named **`glyphs`** (`idle-saver-glyphs` / `libscreensaver_glyphs.so`).
4. Both plugins are fully allowlisted and packaged across RPM and DEB pools.

### Configuration
* `active_saver: "ascii"` is configured as the default screensaver on new installs.
* Users desiring digital matrix rain can switch via `idlescreen saver glyphs` or `active_saver: "glyphs"` in `~/.config/idlescreen/config.yaml`.

---

## 5. Issue 4: Web Installer SHA-256 Checksum Drift

### Root Cause
`curl -fsSL https://idlescreen.github.io/install.sh | sh` aborted at bootstrap with:
```text
install: hash mismatch on bootstrapped module post_install.sh!
install: expected 87129922cb113a6a19a220e6c81f594f5a7e49bd1a90c59d2ed72578c8f16f07,
         got      59fb1fa041728a44742b6dfc7e66df53f1cb6799d09ccdfe0d7733fd51e8fbe2
```
A recent commit updated `post_install.sh` in the repository without recalculating and updating the SHA-256 pin in `install.sh` (line 166).

### Fix
* Run the internal module integrity update script in `idlescreen/packages` (e.g. `./sign_all.sh` or update line 166 in `install.sh`) to synchronize the SHA-256 pins with the deployed modules.

---

## 6. Issue 5: GNOME Wayland Protocol Compatibility Failure

### Symptoms (`idlescreen doctor` output)
```text
[warn] Protocols: DE='GNOME' unrecognized — may lack layer-shell/idle-notify
[FAIL] D-Bus Service: GetStatus error: Remote peer disconnected
[FAIL] Systemd Service: is-active reports 'activating'
[FAIL] Process Status: missing pid file
[FAIL] Inhibitor Status: cannot check — idle-daemon not connected
```

### Journalctl Error Analysis
```text
idle-daemon[...]: Error: DEGRADED: Wayland idle monitoring unavailable (need ext-idle-notify-v1).
                  IdleScreen is a compositor client — this DE/compositor does not expose the idle protocol.
                  See docs/BOUNDARIES.md.
idle-daemon.service: Main process exited, code=exited, status=1/FAILURE
```

### Technical Architecture Detail
1. `idle-daemon/src/daemon/runtime.rs` hard-fails at startup:
   ```rust
   #[cfg(target_os = "linux")]
   let idle_monitor: Box<dyn IdleSource> = {
       use wayland_idle::IdleMonitor;
       let timeout = Duration::from_secs(idle_timeout.saturating_mul(60) as u64);
       Box::new(IdleMonitor::new_timeout(timeout).ok_or_else(|| {
           anyhow!("DEGRADED: Wayland idle monitoring unavailable (need ext-idle-notify-v1)...")
       })?)
   };
   ```
2. GNOME's Wayland compositor (Mutter) **does not implement `ext-idle-notify-v1`** or **`zwlr_layer_shell_v1`**. GNOME manages idle timers internally via the D-Bus interface `org.gnome.Mutter.IdleMonitor`.
3. Because `ext-idle-notify-v1` is missing from Mutter globals, `IdleMonitor::new_timeout()` returns `None`, causing `idle-daemon` to return `Err` and exit with code 1. This drops the D-Bus connection before `GetStatus` can be served.

### Implementation Plan on Dev Server
1. **Session Shell Fallback in Daemon**:
   - In `idle-daemon/src/daemon/runtime.rs`, if `ext-idle-notify-v1` is absent but the DE is GNOME (or when `idle_enabled: false` in config), do NOT exit with code 1.
   - Instead, degrade gracefully: run in passive/listener mode where screensaver presentation is triggered externally (via D-Bus or session lock signals), or hook into `org.gnome.Mutter.IdleMonitor` via D-Bus as a secondary `IdleSource` backend.
2. **GNOME Presentation**:
   - Evaluate fallback presentation on GNOME when `zwlr_layer_shell_v1` is absent (e.g. fullscreen overlay window or GNOME Shell extension bridge).
