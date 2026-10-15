# Trying IdleScreen without changing your session

You can run IdleScreen on a machine that already has a session shell managing
idle and lock, without it taking over anything. This page is the safe way to do
that, what to expect while you are testing, and how to step back.

The short version: **install `idlescreen`, remove the Omarchy hand-off shim if
present, and disable the built-in idle timer (`idlescreen disable`).**

## Why the hand-off shim matters

The unified `idlescreen` package installs `/usr/bin/idlescreen` (daemon, CLI,
TUI, and all 13 built-in GPU shader screensavers) plus the optional
`omarchy-launch-screensaver` session hand-off shim. Removing the shim and
disabling the internal idle timer leaves your existing session untouched while
allowing manual previews.

## Steps

```sh
# 1. Install. This configures the repository and installs the unified idlescreen package.
./install.sh

# 2. Stand the hand-off down before anything can trigger it.
sudo rm -f /usr/local/bin/omarchy-launch-screensaver /usr/bin/omarchy-launch-screensaver

# 3. Make sure IdleScreen never presents on its own.
#    With this off it only ever appears when you ask for it, so there is no
#    way it can compete with the screensaver your session already runs.
idlescreen disable
```

Confirm you are clear:

```sh
command -v omarchy-launch-screensaver    # expect: no output
```

If you have already run the installer once and want a clean slate,
`./install.sh --plan` shows what it would do without doing it.

`idlescreen disable` sets `idle_enabled: false` in
`~/.config/idlescreen/config.yaml`, which switches off IdleScreen's own idle
trigger. Nothing about your existing session changes, and IdleScreen sits
dormant until you tell it to appear.

If you would rather not edit config by hand:

```sh
idlescreen enable     # IdleScreen's idle timer back on
idlescreen disable    # ...and off again
```

## Confirming nothing has been taken over

```sh
idlescreen doctor
```

Look at the **Session shell integration** line:

- **`Warn` — "IdleScreen's own idle timer is off"** is the *expected* result
  while you are testing. It is telling you the timer is off and nothing is
  intercepting, which is exactly the state you asked for.

## Seeing it

Once the idle timer is off, everything is manual:

```sh
idlescreen list                 # built-in savers
idlescreen preview ascii        # fullscreen preview of one saver
idlescreen preview ascii -t 10  # ...that stops itself after 10 seconds
idlescreen start                # present using the configured saver, no auto-stop
idlescreen stop                 # dismiss it
idlescreen tui                  # live configuration UI
```

`idlescreen preview <name>` is the quickest thing to try — it goes fullscreen and
comes back on its own. `idlescreen start` behaves like a real presentation, so
use that to check it covers every monitor and that input dismisses it.

### Trying the artwork

Your session already has branding artwork configured. Point IdleScreen at the
same file so you are comparing like with like:

```yaml
# ~/.config/idlescreen/config.yaml
logo_file: /home/you/.config/omarchy/branding/screensaver.txt
```

## Stepping up to full idle management

Only when you are satisfied:

```sh
idlescreen enable               # give idle timing back to IdleScreen
idlescreen doctor               # should now report the integration as Ok
```

## Going back

Take the whole thing off the machine at any time:

```sh
./install.sh --uninstall
```

## One thing worth knowing

While the daemon is running it owns the standard `org.freedesktop.ScreenSaver`
D-Bus name, which is how applications ask a desktop to start a screensaver.
That is deliberate — it is what lets a screensaver-aware client find IdleScreen.
On a session whose screensaver is not D-Bus driven it changes nothing, but if
you ever see another application behaving oddly around screen blanking, that
name is the first thing to check:

```sh
busctl --user status org.freedesktop.ScreenSaver
```