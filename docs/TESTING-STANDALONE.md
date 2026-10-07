# Trying IdleScreen without changing your session

You can run IdleScreen on a machine that already has a session shell managing
idle and lock, without it taking over anything. This page is the safe way to do
that, what to expect while you are testing, and how to step back.

The short version: **install the four component packages, not the `idlescreen`
metapackage.** The metapackage is the only thing that carries the hand-off
script, so leaving it out means your existing session behaviour is untouched.

## Why the metapackage matters

The Arch packaging splits into five packages:

| Package | What it installs |
| --- | --- |
| `idle-daemon` | the background service |
| `idle-cli` | `/usr/bin/idle-cli` — the controller |
| `idle-savers` | the official screensaver plugins |
| `idle-tui` | the configuration UI |
| `idlescreen` | **the `idlescreen` router command and the session hand-off script** |

Only `idlescreen` contains `omarchy-launch-screensaver`. Install the other four
and you get the daemon, every saver, the CLI and the TUI — with nothing in the
session altered.

The one convenience you give up is the shorter `idlescreen` command name; use
`idle-cli` instead. Every subcommand is identical.

## Steps

```sh
# 1. Install. This configures the repository and installs the full stack —
#    including the metapackage, and therefore the hand-off script.
./install.sh

# 2. Stand the hand-off down before anything can trigger it.
sudo rm -f /usr/local/bin/omarchy-launch-screensaver

# 3. Make sure IdleScreen never presents on its own.
#    With this off it only ever appears when you ask for it, so there is no
#    way it can compete with the screensaver your session already runs.
idle-cli disable
```

Step 2 is why this page exists. `install.sh` installs the `idlescreen`
metapackage, and that package is the only thing that carries
`omarchy-launch-screensaver` — so a fresh install wires the hand-off up
immediately unless you remove it.

Confirm you are clear:

```sh
command -v omarchy-launch-screensaver    # expect: no output
```

If you have already run the installer once and want a clean slate,
`./install.sh --plan` shows what it would do without doing it.

`idle-cli disable` sets `idle_enabled: false` in
`~/.config/idlescreen/config.yaml`, which switches off IdleScreen's own idle
trigger. Nothing about your existing session changes, and IdleScreen sits
dormant until you tell it to appear.

If you would rather not edit config by hand:

```sh
idle-cli enable     # IdleScreen's idle timer back on
idle-cli disable    # ...and off again
```

## Confirming nothing has been taken over

```sh
idle-cli doctor
```

Look at the **Session shell integration** line:

- **`Warn` — "IdleScreen's own idle timer is off but no integration shim is
  installed"** is the *expected* result while you are testing. It is telling you
  the timer is off and nothing is intercepting, which is exactly the state you
  asked for.
- **`Fail`** would mean a hand-off script is present but unreachable. Remove it
  and re-run:

  ```sh
  sudo rm -f /usr/local/bin/omarchy-launch-screensaver
  ```

To be certain nothing of ours is on the path at all:

```sh
command -v omarchy-launch-screensaver    # expect: no output
```

## Seeing it

That is the whole point — once the hand-off is gone, everything is manual.

```sh
idle-cli list                 # installed savers
idle-cli preview ascii        # fullscreen preview of one saver
idle-cli preview ascii -t 10  # ...that stops itself after 10 seconds
idle-cli start                # present using the configured saver, no auto-stop
idle-cli stop                 # dismiss it
idle-cli tui                  # live configuration UI
```

`idle-cli preview <name>` is the quickest thing to try — it goes fullscreen and
comes back on its own. `idle-cli start` is the one that behaves like a real
presentation, so use that to check it covers every monitor and that input
dismisses it.

### Checking idle behaviour properly

You cannot observe automatic idle while the timer is off — that is the point of
turning it off. Once you trust the manual behaviour, the hardware harness
covers the rest:

```sh
cd runtime
./scripts/qa_hardware_parity.sh
```

It drives input, DPMS, suspend/resume and multi-monitor and prints a
pass/fail/skip matrix. Anything it reports as `SKIP` was not actually verified
on your machine — that is a real result, not a pass.

### Trying the artwork

Your session already has branding artwork configured. Point IdleScreen at the
same file so you are comparing like with like:

```yaml
# ~/.config/idlescreen/config.yaml
logo_file: /home/you/.config/omarchy/branding/screensaver.txt
```

## Stepping up to the hand-off

Only when you are satisfied:

```sh
sudo pacman -S idlescreen     # adds the router + hand-off script
idle-cli enable               # give idle timing back to IdleScreen
idle-cli doctor               # should now report the integration as Ok
```

This is the moment your session's idle trigger starts calling IdleScreen. It is
reversible with the next command.

## Going back

```sh
sudo pacman -R idlescreen     # removes the hand-off script
idle-cli enable               # your own idle timer is back
```

Or take the whole thing off the machine:

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