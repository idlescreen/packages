# IdleScreen packages

Signed APT and DNF index: **[idlescreen.github.io/packages](https://idlescreen.github.io/packages/)**

## Users install products

```bash
# Fedora
sudo curl -fsSL https://idlescreen.github.io/packages/rpm/crateria.repo \
  -o /etc/yum.repos.d/idlescreen.repo
sudo dnf install idle-cosmic

# Optional
sudo dnf install idle-tui
```

| Product | Pulls |
|---------|--------|
| **idle-cosmic** | `idle-daemon` + `idle-savers` + applet |
| **idle-tui** | `idle-daemon` + TUI |
| **idle-studio** | offline director |

Engine packages (`idle-daemon`, `idle-cli`, `idle-saver-*`) are **dependencies**, not the advertised install.

CLI command after install: **`idle`**.

## Source

Engine: [idlescreen/idle](https://github.com/idlescreen/idle)
