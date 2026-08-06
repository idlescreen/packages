Name:           idlescreen
Version:        2.6.2
Release:        1
Summary:        IdleScreen product metapackage for Wayland screensavers
License:        Apache-2.0
URL:            https://idlescreen.github.io
BuildArch:      noarch
Requires:       idle-daemon >= 2.5.13
Requires:       idle-cli >= 2.5.0
Requires:       idle-savers
Requires:       idle-tui >= 2.3.2
Recommends:      idle-cosmic >= 2.2.0
Requires(preun): /bin/sh

Source0:        remove-product-stack.sh
Source1:        schedule-remove-stack.sh

%description
Product metapackage for IdleScreen. Pulls in the modular host stack:
idle-daemon, idle-cli, idle-savers, and idle-tui. On COSMIC Desktop,
idle-cosmic is recommended (install.sh adds it when COSMIC is detected).

Install:  sudo dnf install idlescreen
Remove:   sudo dnf remove idlescreen

Removing this package also removes the product stack the installer seated
(idle-daemon, idle-cli, idle-savers, idle-tui, idle-saver-*, idle-cosmic)
and the repo drop-in written by install.sh. User config under ~/.config/idle
is left in place.

%prep
# Sources are scripts only (no tarball).

%build

%install
install -d %{buildroot}%{_libexecdir}/idlescreen
install -m 0755 %{SOURCE0} \
    %{buildroot}%{_libexecdir}/idlescreen/remove-product-stack
install -m 0755 %{SOURCE1} \
    %{buildroot}%{_libexecdir}/idlescreen/schedule-remove-stack

%preun
# $1 == 0 → erase (not upgrade). Schedule stack wipe after this transaction.
if [ "$1" -eq 0 ]; then
    if [ -x %{_libexecdir}/idlescreen/schedule-remove-stack ]; then
        %{_libexecdir}/idlescreen/schedule-remove-stack || true
    fi
fi

%files
%dir %{_libexecdir}/idlescreen
%{_libexecdir}/idlescreen/remove-product-stack
%{_libexecdir}/idlescreen/schedule-remove-stack

%changelog
* Thu Aug 06 2026 IdleScreen <jerydleuck@gmail.com> - 2.6.2-1
- Fix TUI panic when navigating out of bounds in screensaver list
- Fix random screensaver failure when active saver is None
* Sun Jul 26 2026 IdleScreen <jerydleuck@gmail.com> - 2.6.1-1
- Stop user idle-daemon before stack erase; remove empty leftover dirs
* Sun Jul 26 2026 IdleScreen <jerydleuck@gmail.com> - 2.6.0-1
- Erase product stack on dnf remove idlescreen (modules, savers, cosmic, repo drop-in)
* Sat Jul 25 2026 IdleScreen <jerydleuck@gmail.com> - 2.5.0-1
- Product metapackage for modular idle-* stack
