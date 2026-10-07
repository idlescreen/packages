# Session shells that own idle and lock

IdleScreen works two ways, and which one you get depends on whether your
session already owns idle timing.

- **No such shell installed** — IdleScreen runs its own idle timer and presents
  the screensaver itself. Nothing else is involved.
- **A session shell is installed** — that shell keeps ownership of *when* to go
  idle and of *locking the screen*. IdleScreen takes over only the job of
  drawing. It stands its own idle trigger down so the two never race.

The second case is the one this document is about.

**Supported today:** Omarchy. Its idle service calls
`omarchy-launch-screensaver` when the session goes idle, so that is the name
IdleScreen steps in front of. GNOME, COSMIC, Hyprland and Sway sessions work too,
but they run IdleScreen's own idle timer — they do not hand off idle timing to
IdleScreen and do not need to.

## Why the split exists

Two independent things can go idle in a session:

1. **Idle detection** — deciding the user walked away.
2. **Locking** — securing the screen once idle.

Session shells that own idle policy already do both. If IdleScreen also ran its
own timer, you would get two screensavers on two different clocks: one appears
at five minutes, another at eight, and neither explains the other.

So when a session shell is detected, IdleScreen sets `idle_enabled: false` and
lets the shell call it instead. The shell decides *when*; IdleScreen decides
*what you see*.

## How the hand-off happens

The shell invokes a single command by name when its idle timer fires. IdleScreen
installs a small script under that same name, earlier on `PATH`, which:

1. honours the shell's own "screensaver off" toggle,
2. stands aside entirely if the screen is already locked,
3. stands aside if anything holds a session idle inhibitor,
4. otherwise hands off to `idlescreen start`.

The result is a zero-latency hand-off with no polling: the shell fires its own
command, and IdleScreen draws.

## Verifying it

```sh
idlescreen doctor
```

The "Session shell integration" check reports exactly what happened:

| Result | Meaning | Fix |
| --- | --- | --- |
| `Ok` | The shell drives the trigger and IdleScreen draws. | — |
| `Warn` | Both idle triggers are live, so you may see two savers. | `idlescreen disable` |
| `Warn` | IdleScreen's trigger is off but nothing will call it. | `idlescreen enable` |
| `Fail` | The integration script cannot be reached. | `reinstall idlescreen` |

The check is deliberately blunt about the `Fail` case. A hand-off script that
exists on disk but loses the `PATH` lookup does nothing at all, and looks
perfectly healthy from the daemon's own status — so `doctor` resolves the name
the same way the shell does and reports which file actually wins.

## Turning it off

If you would rather IdleScreen ran its own timer:

```sh
idlescreen disable      # IdleScreen's idle trigger back on
idlescreen enable       # ...and back off again
```

Re-running the installer is idempotent here. It sets `idle_enabled: false` only
when the key is absent; if you have deliberately set `true`, it leaves your
choice alone and tells you how to change it.

## Uninstalling

The hand-off script lives in `/usr/local/bin`, outside every package tree, so no
package manager removes it. `idlescreen uninstall` deletes it explicitly —
otherwise it would outlive the daemon and shadow the shell's own launcher.

## Adding your own ASCII art

Set `logo_file` in `~/.config/idlescreen/config.yaml` to an absolute path:

```yaml
logo_file: /home/you/.config/idlescreen/logo.txt
```

The daemon reads that file and hands the contents to the renderer. The
renderer and the saver plugin never open the file themselves, which is why no
extra permission is needed and the plugin sandbox is unchanged.

- The path must be absolute — a relative path would resolve against the daemon's
  working directory, which nothing in a config file can explain.
- Files over 64 KiB are refused rather than truncated, so a half-drawn logo can
  never be mistaken for a rendering bug.
- A configured-but-unreadable path is logged and ignored. A missing logo must
  never stop the screensaver from appearing.
- Savers read it with `idle_api::asset("logo")`, which returns `None` when no art
  is configured — the common case, and never an error.