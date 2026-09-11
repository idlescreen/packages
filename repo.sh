# shellcheck shell=sh
# Repo logic
REPO_BASE="https://idlescreen.github.io/packages"

# Fingerprint of the IdleScreen RPM signing key (rpm/idlescreen-key.gpg).
# Pinned so the DNF trust anchor is verified the same way the APT keyring is.
RPM_KEY_FPR="3D2D670DBD9BD94D7B2D23D356ED99E8C0243160"

# System dirs; env-overridable for the mock-package-manager smoke test.
RPM_GPG_DIR="${IDLESCREEN_RPM_GPG_DIR:-/etc/pki/rpm-gpg}"
YUM_REPOS_D="${IDLESCREEN_YUM_REPOS_D:-/etc/yum.repos.d}"

setup_repo_dnf() {
    step "[2/5]  Opening the package gate  ·  RPM repository"
    story_line "Fetching + fingerprint-checking the IdleScreen RPM signing key…"
    pause 0.3
    _tmp_key=$(mktemp)
    if ! curl -fsSL "${REPO_BASE}/rpm/idlescreen-key.gpg" -o "$_tmp_key"; then
        err "Could not download RPM signing key from ${REPO_BASE}/rpm/idlescreen-key.gpg"
        rm -f "$_tmp_key"
        exit 1
    fi
    # The key file may carry both the Ed25519 and RSA keys — the pin holds
    # when the expected fingerprint is among the primary-key fingerprints.
    if ! gpg --show-keys --with-colons "$_tmp_key" 2>/dev/null \
        | awk -F: '/^fpr:/ {print $10}' | grep -qx "$RPM_KEY_FPR"; then
        err "RPM signing key fingerprint mismatch! ($RPM_KEY_FPR not present in key file)"
        rm -f "$_tmp_key"
        exit 1
    fi
    sudo mkdir -p "$RPM_GPG_DIR"
    sudo mv "$_tmp_key" "$RPM_GPG_DIR/idlescreen-key.gpg"
    sudo chmod 644 "$RPM_GPG_DIR/idlescreen-key.gpg"
    sudo rpm --import "$RPM_GPG_DIR/idlescreen-key.gpg" 2>/dev/null || true
    ok "RPM key → ${BOLD}${RPM_GPG_DIR}/idlescreen-key.gpg${RESET} (fingerprint verified)"

    # The .repo file is written from pinned content, never fetched: a fetched
    # .repo's gpgkey/baseurl would let a compromised origin swap the trust
    # anchor entirely. gpgkey points at the fingerprint-verified local file.
    story_line "Writing IdleScreen DNF repo file (pinned content)…"
    sudo mkdir -p "$YUM_REPOS_D"
    printf '%s\n' \
        "[idlescreen]" \
        "name=IdleScreen RPM Repository" \
        "baseurl=${REPO_BASE}/rpm" \
        "enabled=1" \
        "gpgcheck=1" \
        "repo_gpgcheck=1" \
        "gpgkey=file://${RPM_GPG_DIR}/idlescreen-key.gpg" \
        "metadata_expire=1h" \
        | sudo tee "${YUM_REPOS_D}/idlescreen.repo" >/dev/null
    ok "Repo written → ${BOLD}${YUM_REPOS_D}/idlescreen.repo${RESET}"
    dim "   baseurl ${REPO_BASE}/rpm  ·  package gpgcheck=1  ·  repo_gpgcheck=1"
    story_line "Refreshing IdleScreen channel metadata…"
    sudo dnf clean metadata --repo=idlescreen >/dev/null 2>&1 || true
    _meta_ok=0
    if [ "$IS_TTY" -eq 1 ]; then
        sudo dnf makecache --refresh --repo=idlescreen >/dev/null 2>&1 &
        if spin_while $! "syncing DNF metadata"; then
            _meta_ok=1
        elif sudo dnf makecache --refresh >/dev/null 2>&1; then
            _meta_ok=1
        fi
    else
        if sudo dnf makecache --refresh --repo=idlescreen >/dev/null 2>&1 \
            || sudo dnf makecache --refresh >/dev/null 2>&1; then
            _meta_ok=1
        fi
    fi
    if [ "$_meta_ok" -eq 1 ]; then
        ok "DNF metadata refreshed for this session"
    else
        warn "Could not refresh DNF metadata — install will still try the channel"
    fi
}

setup_repo_apt() {
    step "[2/5]  Opening the package gate  ·  APT repository"
    story_line "Creating /etc/apt/keyrings if needed…"
    sudo mkdir -p /etc/apt/keyrings
    story_line "Downloading IdleScreen APT signing keyring…"
    _tmp_key=$(mktemp)
    if ! curl -fsSL "${REPO_BASE}/apt/idlescreen-keyring.gpg" -o "$_tmp_key"; then
        err "Could not download APT keyring from ${REPO_BASE}/apt/idlescreen-keyring.gpg"
        rm -f "$_tmp_key"
        exit 1
    fi
    if ! gpg --show-keys --with-colons "$_tmp_key" 2>/dev/null \
        | awk -F: '/^fpr:/ {print $10}' | grep -qx "549E73C9BC9229C786E538E2FBD8FC52C7817DD2"; then
        err "APT keyring fingerprint mismatch!"
        rm -f "$_tmp_key"
        exit 1
    fi
    sudo mv "$_tmp_key" /etc/apt/keyrings/idlescreen-keyring.gpg
    sudo chmod 644 /etc/apt/keyrings/idlescreen-keyring.gpg
    ok "Keyring → ${BOLD}/etc/apt/keyrings/idlescreen-keyring.gpg${RESET}"
    story_line "Writing APT source list (stable/main, signed-by keyring)…"
    echo "deb [signed-by=/etc/apt/keyrings/idlescreen-keyring.gpg] ${REPO_BASE}/apt/ stable main" \
        | sudo tee /etc/apt/sources.list.d/idlescreen.list >/dev/null
    story_line "Running apt-get update…"
    if [ "$IS_TTY" -eq 1 ]; then
        sudo apt-get update -qq &
        spin_while $! "syncing APT metadata" || {
            err "apt-get update failed"
            exit 1
        }
    else
        sudo apt-get update -qq
    fi
    ok "APT index updated with IdleScreen source"
}

version_is_older() {
    _a="$1"
    _b="$2"
    if [ -z "$_a" ] || [ -z "$_b" ]; then
        return 1
    fi
    if [ "$_a" = "$_b" ]; then
        return 1
    fi
    _first=$(printf '%s\n%s\n' "$_a" "$_b" | sort -V | head -n 1)
    [ "$_first" = "$_a" ]
}

rpm_installed_ver() {
    rpm -q --qf '%{VERSION}-%{RELEASE}' "$1" 2>/dev/null || true
}

rpm_available_ver() {
    _pkg="$1"
    _v=""
    for _fmt_flag in "--queryformat=%{version}-%{release}\n" "--qf=%{version}-%{release}"; do
        _v=$(dnf -q repoquery --repo=idlescreen --latest-limit=1 \
            "$_fmt_flag" "$_pkg" 2>/dev/null | head -n 1 | tr -d '\r')
        if [ -n "$_v" ] && ! printf '%s' "$_v" | grep -q '%{'; then
            printf '%s' "$_v"
            return 0
        fi
        _v=$(dnf -q repoquery --latest-limit=1 \
            "$_fmt_flag" "$_pkg" 2>/dev/null | head -n 1 | tr -d '\r')
        if [ -n "$_v" ] && ! printf '%s' "$_v" | grep -q '%{'; then
            printf '%s' "$_v"
            return 0
        fi
    done
    _nevra=$(dnf -q repoquery --repo=idlescreen --latest-limit=1 "$_pkg" 2>/dev/null | head -n 1)
    if [ -z "$_nevra" ]; then
        _nevra=$(dnf -q repoquery --latest-limit=1 "$_pkg" 2>/dev/null | head -n 1)
    fi
    if [ -n "$_nevra" ]; then
        _base=${_nevra%.*}
        _vr=$(printf '%s' "$_base" | sed -E 's/^[a-z0-9+._-]+-([0-9].*)$/\1/; t; s/^[a-z0-9+._-]+:([0-9].*)$/\1/')
        _vr=$(printf '%s' "$_vr" | sed -E 's/^[0-9]+://')
        printf '%s' "$_vr"
        return 0
    fi
    printf ''
}

apt_installed_ver() {
    dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true
}

apt_candidate_ver() {
    apt-cache policy "$1" 2>/dev/null \
        | awk '/Candidate:/ { print $2; exit }' \
        | grep -v '^(none)$' || true
}
