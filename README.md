# DualSense Agent Bridge

Use a PlayStation 5 DualSense controller to drive terminal-based coding
sessions on macOS.

The project is intended to make Codex, Claude Code, and other tmux-backed
sessions usable from a controller plus Wispr Flow:

- a dedicated controller action starts/stops Wispr Flow press-to-talk;
- Cross sends Enter and Circle cancels;
- R3 interrupts the focused session with Ctrl-C;
- the D-pad changes the active tmux session;
- the sticks can become mouse/scroll controls;
- the latest safe response can be spoken locally with macOS `say`.

This is an early, macOS-first open-source project. The first milestone favors
an observable CLI/daemon and deterministic fake-input tests before adding a
menu-bar shell or provider-specific transcript parsers.

## Requirements

- macOS 13 or newer
- Swift 6 / Xcode command-line tools
- A paired DualSense controller (USB is recommended for controller-audio work)
- Accessibility permission for synthetic keyboard and mouse events
- Wispr Flow configured with a unique accepted keyboard shortcut
- tmux for session control

## Usage

```sh
swift build
swift run dualsense-bridge help            # commands and options
swift run dualsense-bridge doctor          # permission, profile, attached controllers
swift run dualsense-bridge controls        # control names accepted in a profile
swift run dualsense-bridge profile         # print the active profile as JSON
swift run dualsense-bridge run --dry-run   # log actions without emitting keys
swift run dualsense-bridge run             # bridge controller input to the keyboard
```

`run` refuses to start without Accessibility permission and prints the exact
steps to grant it. Control-C or `kill` releases every synthetic key it holds,
and so does a controller disconnect — even if Accessibility permission is
revoked while a chord is down.

### Run it in its own terminal

The bridge emits ordinary keyboard events, so they land in whatever window has
focus. Start it from a terminal inside the Mac's logged-in GUI session, then
leave that window in the background and focus the local or SSH-backed agent
session you actually want to control. A bridge process launched by a plain SSH
login can discover a controller but does not reliably receive its HID input. If
the bridge's own terminal is focused, Cross and R3 act on that terminal instead.

Because of that, the bridge is almost never the frontmost application, and since
macOS 11.3 GameController drops controller input for processes that are not
frontmost. `run` therefore enables background controller monitoring before it
looks for a controller, and prints the result:

```text
Background controller events: enabled
```

If that line ever says `DISABLED`, the controller will connect and every button
press will be silently dropped. The setting is process-global, so `run` puts the
previous value back when it stops.

### Starter profile

| Control | Action | Keys |
| --- | --- | --- |
| `l2` | hold | `control+option+space` (Wispr Flow press-to-talk) |
| `cross` | tap | `return` |
| `circle` | tap | `escape` |
| `r3` | tap | `control+c` |

The DualSense mic button is intentionally left unbound so it keeps its hardware
mute behavior.

Set the Wispr Flow dictation shortcut to the same keys as the `hold` binding.
Any unique chord built from `control`, `option`, `shift`, and `command` plus one
key works; `fn` cannot be emitted synthetically and is rejected with an
explanation.

### Changing the mapping

Bindings are data, not code. Seed a profile with `--starter`, which prints the
built-in profile without reading any file, and rename it into place. Do not
redirect straight onto the destination: the shell truncates the target file
before the command runs, which would destroy an existing profile.

```sh
swift run dualsense-bridge profile --starter > /tmp/dualsense-profile.json
mkdir -p ~/.config/dualsense-bridge
mv /tmp/dualsense-profile.json ~/.config/dualsense-bridge/profile.json
```

Edit that file, then run `dualsense-bridge doctor` to validate it. A profile is
versioned (`schemaVersion`) and validated strictly: an unknown control name,
unknown binding kind, or unparseable shortcut is refused with a message instead
of being silently ignored, so a typo cannot quietly disable the interrupt
binding. Use `--profile <path>` to load a profile from another location.

## Development

```sh
swift test
swift build
```

Behavior is tested through a fake input source and a fake keyboard sink, so
press/release ordering, duplicate and out-of-order events, held-key cleanup on
disconnect and shutdown, and the Accessibility refusal path all run without a
controller attached.

Hardware checks live in
[docs/smoke/s1-controller-wispr.md](docs/smoke/s1-controller-wispr.md). Do not
paste real session output or credentials into issues, fixtures, or logs.

## License

MIT. See [LICENSE](LICENSE).
