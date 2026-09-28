#!/bin/sh
# install-studio helper: write the IdleScreen package channel
# (DNF or APT). Sets $PKG so the install/verify helpers can
# dispatch on it.
#
# Both branches pin the signing-key fingerprint out-of-band so a
# compromised Pages origin cannot swap the trust anchor. The
# .repo / sources.list file is *written from pinned content* —
# never fetched — so the trust anchor (gpgkey / baseurl) is
# always what the installer author committed.

write_channel() {
    if [ "$PKG" = "dnf" ]; then
        write_channel_dnf
    else
        write_channel_apt
    fi
}

write_channel_dnf() {
    need_cmd curl
    need_cmd sudo
    need_cmd gpg
    _tmp_key=$(mktemp)
    if ! curl -fsSL "${REPO_BASE}/rpm/idlescreen-key.gpg" -o "$_tmp_key"; then
        err "could not download RPM signing key"
        rm -f "$_tmp_key"
        exit 1
    fi
    _fpr=$(gpg --show-keys --with-colons "$_tmp_key" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')
    if [ "$_fpr" != "$RPM_KEY_FPR" ]; then
        err "RPM signing key fingerprint mismatch (got ${_fpr:-none})"
        rm -f "$_tmp_key"
        exit 1
    fi
    sudo mkdir -p /etc/pki/rpm-gpg
    sudo mv "$_tmp_key" /etc/pki/rpm-gpg/idlescreen-key.gpg
    sudo chmod 644 /etc/pki/rpm-gpg/idlescreen-key.gpg
    sudo rpm --import /etc/pki/rpm-gpg/idlescreen-key.gpg 2>/dev/null || true
    ok "RPM key → /etc/pki/rpm-gpg/idlescreen-key.gpg (fingerprint verified)"
    printf '%s\n' \
        "[idlescreen]" \
        "name=IdleScreen RPM Repository" \
        "baseurl=${REPO_BASE}/rpm" \
        "enabled=1" \
        "gpgcheck=1" \
        "repo_gpgcheck=1" \
        "gpgkey=file:///etc/pki/rpm-gpg/idlescreen-key.gpg" \
        "metadata_expire=1h" \
        | sudo tee /etc/yum.repos.d/idlescreen.repo >/dev/null
    ok "repo → /etc/yum.repos.d/idlescreen.repo"
    say "  ${DIM}baseurl ${REPO_BASE}/rpm · package gpgcheck=1 · repo_gpgcheck=1${RESET}"
    sudo dnf clean all --repo=idlescreen >/dev/null 2>&1 || true
    sudo dnf clean metadata --repo=idlescreen >/dev/null 2>&1 || true
    sudo dnf makecache --refresh --repo=idlescreen >/dev/null 2>&1 \
        || sudo dnf --setopt=idlescreen.metadata_expire=0 makecache --repo=idlescreen >/dev/null 2>&1 \
        || warn "metadata refresh soft-failed — install will still try the channel"
}

write_channel_apt() {
    need_cmd curl
    need_cmd sudo
    need_cmd gpg
    sudo mkdir -p /etc/apt/keyrings
    _tmp_key=$(mktemp)
    if ! curl -fsSL "${REPO_BASE}/apt/idlescreen-keyring.gpg" -o "$_tmp_key"; then
        err "could not download APT keyring"
        rm -f "$_tmp_key"
        exit 1
    fi
    _fpr=$(gpg --show-keys --with-colons "$_tmp_key" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')
    if [ "$_fpr" != "$APT_KEY_FPR" ]; then
        err "APT keyring fingerprint mismatch (got ${_fpr:-none})"
        rm -f "$_tmp_key"
        exit 1
    fi
    sudo mv "$_tmp_key" /etc/apt/keyrings/idlescreen-keyring.gpg
    sudo chmod 644 /etc/apt/keyrings/idlescreen-keyring.gpg
    ok "keyring → /etc/apt/keyrings/idlescreen-keyring.gpg (fingerprint verified)"
    echo "deb [signed-by=/etc/apt/keyrings/idlescreen-keyring.gpg] ${REPO_BASE}/apt/ stable main" \
        | sudo tee /etc/apt/sources.list.d/idlescreen.list >/dev/null
    ok "source → /etc/apt/sources.list.d/idlescreen.list"
    sudo apt-get update -qq
    ok "APT index updated"
}