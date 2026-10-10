# Compositor Recipes & Keybindings

IdleScreen integrates natively with Wayland compositors via `ext-idle-notify-v1` and `wlr-layer-shell`. When running on a standalone desktop environment or tiling compositor (such as Hyprland, Sway, Wayfire, River, or Labwc), you can configure keybindings, idle daemons (`hypridle`, `swayidle`), and status bars (`waybar`).

---

## 1. Hyprland Integration

### Hyprland Keybindings (`~/.config/hypr/hyprland.conf`)

Add hotkeys to immediately trigger the screensaver or toggle idle standby:

```ini
# Start screensaver immediately
bind = $mainMod SHIFT, S, exec, idlescreen start

# Toggle stay-awake / idle monitoring (similar to coffee cup mode)
bind = $mainMod CTRL, I, exec, idlescreen toggle

# Stop screensaver if triggered manually
bind = $mainMod CTRL, Escape, exec, idlescreen stop
```

### Two-Stage Idle Configuration with `hypridle` (`~/.config/hypr/hypridle.conf`)

To coordinate screensaver presentation, lock screen (e.g., `hyprlock`), and DPMS display sleep in stages:

```ini
general {
    lock_cmd = pidof hyprlock || hyprlock
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd = hyprctl dispatch dpms on
}

# Stage 1: Trigger screensaver after 2.5 minutes (150 seconds)
listener {
    timeout = 150
    on-timeout = idlescreen start
    on-resume = idlescreen stop
}

# Stage 2: Lock the session after 5 minutes (300 seconds)
listener {
    timeout = 300
    on-timeout = loginctl lock-session
}

# Stage 3: Turn off display backlights after 5.5 minutes (330 seconds)
listener {
    timeout = 330
    on-timeout = hyprctl dispatch dpms off
    on-resume = hyprctl dispatch dpms on
}
```

> [!NOTE]
> If you configure `hypridle` to drive `idlescreen start`, run `idlescreen disable` (or set `idle_enabled: false` in `~/.config/idlescreen/config.toml`) so that both daemons do not race on separate clocks.

---

## 2. Sway & Swayidle Integration

### Sway Keybindings (`~/.config/sway/config`)

```ini
# Manual trigger
bindsym $mod+Shift+s exec idlescreen start

# Toggle stay-awake standby
bindsym $mod+Ctrl+i exec idlescreen toggle
```

### `swayidle` Configuration

```sh
swayidle -w \
    timeout 150 'idlescreen start' resume 'idlescreen stop' \
    timeout 300 'swaylock -f' \
    timeout 330 'swaymsg "output * power off"' resume 'swaymsg "output * power on"' \
    before-sleep 'swaylock -f'
```

---

## 3. Waybar Stay-Awake Status Indicator

Add a custom stay-awake toggle module to `~/.config/waybar/config`:

```json
"custom/idlescreen": {
    "format": "{icon}",
    "format-icons": {
        "active": "󰾪",
        "inactive": "󰒲"
    },
    "return-type": "json",
    "exec": "idlescreen status --json 2>/dev/null | jq -c '{alt: (if .active or .service_active then \"active\" else \"inactive\" end), tooltip: (if .active or .service_active then \"IdleScreen: Active\" else \"IdleScreen: Standby/Stay-Awake\" end)}'",
    "interval": 5,
    "on-click": "idlescreen toggle"
}
```

---

## 4. Omarchy Coexistence Notes

If you are running [Omarchy](https://omarchy.org/):

- Omarchy provides its own session shell that manages the idle timeout (`~/.config/omarchy/shell.json`) and binds `Super + Ctrl + I` to Omarchy's coffee cup stay-awake indicator.
- Omarchy delegates screensaver rendering to IdleScreen via `/usr/local/bin/omarchy-launch-screensaver`.
- **Do not** rebind `Super + Ctrl + I` or `Super + Esc` in Omarchy, as doing so bypasses Omarchy's top-bar status indicators and screen lock inhibitor. IdleScreen automatically honors Omarchy's toggles and inhibitors.
