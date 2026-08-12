# Repo logic
REPO_BASE="https://idlescreen.github.io/packages"

setup_repo_dnf() {
    step "[2/5]  Opening the package gate  ·  RPM repository"
    story_line "Writing IdleScreen DNF repo file…"
    pause 0.3
    sudo curl -fsSL "${REPO_BASE}/rpm/idlescreen.repo" \
        -o /etc/yum.repos.d/idlescreen.repo
    ok "Repo written → ${BOLD}/etc/yum.repos.d/idlescreen.repo${RESET}"
    dim "   baseurl ${REPO_BASE}/rpm  ·  package gpgcheck=1  ·  repo_gpgcheck=0"
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
    _fpr=$(gpg --show-keys --with-colons "$_tmp_key" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')
    if [ "$_fpr" != "549E73C9BC9229C786E538E2FBD8FC52C7817DD2" ]; then
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
