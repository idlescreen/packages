Name:           idlescreen
Version:        2.4.0
Release:        1
Summary:        IdleScreen product metapackage for Wayland screensavers
License:        Apache-2.0
URL:            https://idlescreen.github.io
BuildArch:      noarch
Requires:       idle-daemon
Requires:       idle-cli
Requires:       idle-savers
Requires:       idle-tui
Recommends:      idle-cosmic

%description
Product metapackage for IdleScreen. Pulls in the modular host stack:
idle-daemon, idle-cli, idle-savers, and idle-tui. On COSMIC Desktop,
idle-cosmic is recommended (install.sh adds it when COSMIC is detected).

Install:  sudo dnf install idlescreen
Remove:   sudo dnf remove idlescreen

%prep
%build
%install
%files
%changelog
* Fri Jul 25 2026 IdleScreen <jerydleuck@gmail.com> - 2.4.0-1
- Product metapackage for modular idle-* stack
