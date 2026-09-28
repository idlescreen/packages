#!/bin/sh
# install-studio helper: have_ffmpeg + ensure_ffmpeg.
#
# ffmpeg is a render dependency — encodes need /usr/bin/ffmpeg on
# PATH. The installer tries `ffmpeg-free` first on Fedora (the
# default repo) and falls back to the full `ffmpeg` package when
# the restricted-multimedia repo is configured.

have_ffmpeg() {
    [ -x /usr/bin/ffmpeg ] || command -v ffmpeg >/dev/null 2>&1
}

ensure_ffmpeg() {
    if have_ffmpeg; then
        ok "ffmpeg → $(command -v ffmpeg 2>/dev/null || echo /usr/bin/ffmpeg)"
        return 0
    fi
    step "  Installing an ffmpeg package"
    if [ "$PKG" = "dnf" ]; then
        if sudo dnf install -y ffmpeg-free 2>/dev/null; then
            ok "installed ffmpeg-free"
        elif sudo dnf install -y ffmpeg 2>/dev/null; then
            ok "installed ffmpeg"
        else
            warn "could not install ffmpeg-free or ffmpeg — encodes need /usr/bin/ffmpeg"
            return 1
        fi
    else
        if sudo apt-get install -y ffmpeg 2>/dev/null; then
            ok "installed ffmpeg"
        else
            warn "could not install ffmpeg — encodes need the ffmpeg package"
            return 1
        fi
    fi
    have_ffmpeg
}