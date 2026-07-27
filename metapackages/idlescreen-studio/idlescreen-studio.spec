Name:           idlescreen-studio
Version:        1.0.0
Release:        1
Summary:        IdleScreen Studio product metapackage (offline render Director)
License:        Apache-2.0
URL:            https://idlescreen.github.io
BuildArch:      noarch
Requires:       idle-studio >= 0.3.3
Requires:       render >= 0.3.3
Recommends:      idle-savers
Requires(preun): /bin/sh

Source0:        remove-studio-stack.sh
Source1:        schedule-remove-studio-stack.sh

%description
Product metapackage for IdleScreen Studio. Pulls in:
  idle-studio  (TUI Director)
  render       (offline export binary)

Install:  sudo dnf install idlescreen-studio
          curl -fsSL https://idlescreen.github.io/packages/install-studio.sh | sh
Remove:   sudo dnf remove idlescreen-studio

Removing this package also removes idle-studio and render.
It does not remove idle-savers, ffmpeg, or the desktop IdleScreen host stack.

%prep

%build

%install
install -d %{buildroot}%{_libexecdir}/idlescreen-studio
install -m 0755 %{SOURCE0} \
    %{buildroot}%{_libexecdir}/idlescreen-studio/remove-studio-stack
install -m 0755 %{SOURCE1} \
    %{buildroot}%{_libexecdir}/idlescreen-studio/schedule-remove-studio-stack

%preun
if [ "$1" -eq 0 ]; then
    if [ -x %{_libexecdir}/idlescreen-studio/schedule-remove-studio-stack ]; then
        %{_libexecdir}/idlescreen-studio/schedule-remove-studio-stack || true
    fi
fi

%files
%dir %{_libexecdir}/idlescreen-studio
%{_libexecdir}/idlescreen-studio/remove-studio-stack
%{_libexecdir}/idlescreen-studio/schedule-remove-studio-stack

%changelog
* Mon Jul 27 2026 IdleScreen <jerydleuck@gmail.com> - 1.0.0-1
- Product metapackage: Requires idle-studio + render; wipe both on erase
