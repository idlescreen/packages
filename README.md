[![secured by studio2201](https://img.shields.io/badge/secured%20by-studio2201-2f6f5e?logo=shield)](https://studio2201.com)

# packages

[![snip](https://img.shields.io/github/actions/workflow/status/idlescreen/packages/snip.yml?label=snip&logo=shield)](https://github.com/idlescreen/packages/actions/workflows/snip.yml)
[![vigil](https://img.shields.io/github/actions/workflow/status/idlescreen/packages/vigil.yml?label=vigil&logo=shield)](https://github.com/idlescreen/packages/actions/workflows/vigil.yml)
[![aegis](https://img.shields.io/github/actions/workflow/status/idlescreen/packages/aegis.yml?label=aegis&logo=shield)](https://github.com/idlescreen/packages/actions/workflows/aegis.yml)
[![proven](https://img.shields.io/github/actions/workflow/status/idlescreen/packages/proven.yml?label=proven&logo=shield)](https://github.com/idlescreen/packages/actions/workflows/proven.yml)
[![boneyard](https://img.shields.io/github/actions/workflow/status/idlescreen/packages/boneyard.yml?label=boneyard&logo=shield)](https://github.com/idlescreen/packages/actions/workflows/boneyard.yml)

The signed package channel — APT and RPM repos served at
`idlescreen.github.io/packages`, fed by release imports from every product
repo. Part of [IdleScreen](https://idlescreen.github.io) — modular Wayland
screensavers for Linux.

## Install

```sh
curl -fsSL https://idlescreen.github.io/install.sh | sh
```

The installer writes the repo config + GPG key, then installs the
`idlescreen` product package — the router that pulls the whole stack.
See `TRUST.md` for the trust model and signature verification.

## License

Apache-2.0 · © 2026 IdleScreen

---

<div align="center">

[![Necrometer](necrometer.svg)](https://necrometer.dev/?u=idlescreen)

</div>
