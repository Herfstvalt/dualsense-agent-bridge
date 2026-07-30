# DualSense Agent Bridge

Use a PlayStation 5 DualSense controller to drive terminal-based coding
sessions on macOS.

The project is intended to make Codex, Claude Code, and other tmux-backed
sessions usable from a controller plus Wispr Flow:

- R3 starts/stops Wispr Flow through a reliably held Ctrl-S toggle shortcut;
- Cross sends Enter and Circle cancels;
- the shoulder buttons drive tmux windows and the session list;
- the D-pad walks shell history;
- the right stick moves the pointer and the left stick scrolls;
- the touchpad moves the pointer only, including when more than one finger is down;
- R2 holds left click and L2 holds right click, including drag gestures;
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
| `r3` | hold for physical click | `control+s` (Wispr Flow toggle) |
| `cross` | tap | `return` |
| `circle` | tap | `escape` |
| `square` | repeat | `delete` (Backspace) |
| `triangle` | tap | `option+command+f5` (Accessibility Shortcuts) |
| `touchpadButton` | tap | `control+grave` |
| `r1` | tapSequence | `control+b, n` (tmux next window) |
| `l1` | tapSequence | `control+b, p` (tmux previous window) |
| `l3` | tapSequence | `control+b, s` (tmux session list) |
| `dpadUp` | tap | `arrowUp` |
| `dpadDown` | tap | `arrowDown` |
| `dpadLeft` | tap | `control+z` (resize/undo action) |
| `dpadRight` | tap | `control+c` (copy-last action; terminal interrupt elsewhere) |
| `options` | tap | `control+v` (paste action) |

| Control | Action |
| --- | --- |
| right stick | move the pointer — deadzone 0.15, curve 2.0, 1200 px/s |
| left stick | scroll — deadzone 0.2, curve 2.0, 500 px/s |
| touchpad | move the pointer relative to the contacts' average travel |
| `r2` | hold the left mouse button |
| `l2` | hold the right mouse button |

A `tapSequence` sends each shortcut as a complete press *and release*, in order.
That is what the tmux bindings need: tmux reads `control+b` and then the command
key as two separate keystrokes, so sending them as one chord would not work. It
is only an ordered list — there are no delays, repeats, or nesting, because a
binding that can express timing stops being a binding and becomes a macro
language.

A `repeat` binding sends one key-down immediately, waits 400 ms, then emits
native repeat events every 50 ms until the controller button is released. This
gives Square normal keyboard-style Backspace behavior: tap for one deletion or
hold to keep deleting.

The DualSense mic button keeps its hardware mute, while R2 and L2 belong to the
pointer boundary rather than keyboard routing. Square is deliberately a
repeating Backspace. Triangle opens macOS Accessibility Shortcuts, the supported
route to enable the on-screen Accessibility Keyboard. Those face-button
mappings remain ordinary profile data and can be replaced.

### Stick and touchpad navigation

The right stick moves the macOS pointer and the left stick scrolls the focused
view, both continuously while the stick is held.

Holding R2 presses the left mouse button; holding L2 presses the right mouse
button. Pointer motion while either trigger is held emits the matching native
left- or right-drag event rather than a plain move. Releasing the trigger lifts
that button and motion returns to ordinary cursor movement.

That makes R2 suitable for selection and ordinary dragging, and L2 suitable for
context menus or app-specific right-drag gestures. If both are held, left drag
has priority until R2 is released.

The touch surface is event-driven rather than tick-driven. The first contact
point becomes a baseline, so landing on an edge never jumps the cursor. Every
active contact contributes to relative cursor motion through the contacts'
average movement; adding a second finger never turns into scrolling or a system
swipe. The physical touchpad *click* remains the separate Ctrl-backtick terminal
shortcut.

These are pointer events, not synthetic system-level multitouch. macOS does not
expose a supported way for this bridge to inject three- or four-finger Mission
Control/Spaces gestures, and the bridge deliberately emits no touchpad scroll
events that could be mistaken for one.

A held mouse button is worse to leave latched than a held key, so both are
released on every exit: trigger release, controller disconnect/reconnect, a
profile change, shutdown, and process teardown. Cleanup deliberately ignores the
Accessibility permission check, because revoking permission mid-drag must not be
able to leave the button down. Pausing mid-drag is safe: the stick returning to
centre drops the sub-pixel remainder but does not release the button.

Four knobs shape the feel, per stick, and none of them needs a rebuild:

| Setting | Meaning |
| --- | --- |
| `deadzone` | Deflection below this does nothing, so a worn stick cannot drift the cursor. |
| `responseExponent` | 1 is linear; higher values make small pushes finer while full deflection still reaches full speed. |
| `speed` | Pixels per second at full deflection. |
| `invertX` / `invertY` | Flip an axis if it feels backwards on your setup. |

Two more values apply to both sticks: `tickInterval`, how often motion is
recomputed, and `maximumTickInterval`, the most travel a single tick may account
for. That clamp is what stops a stalled or suspended process from flinging the
cursor across the screen when it resumes.

Motion is driven by a clock, not by stick callbacks. A gamepad reports a stick
only when its value *changes*, so a stick held at full deflection goes quiet after
one report; anything driven by callbacks alone would twitch once and stop.
Releasing the stick stops output on the next tick, and a disconnect, a profile
change, or shutdown stops it immediately.

`run --dry-run` reports motion as periodic summaries rather than one line per
tick, which is what makes it usable for tuning:

```text
  mouse dx=+318 dy=-96 over 0.50s (61 samples)
  scroll dx=+0 dy=-140 over 0.50s (61 samples)
  left button down
  left drag dx=+84 dy=+12 over 0.50s (61 samples)
  left button up
```

Drag motion is summarized separately from ordinary motion, and button
transitions are never throttled, so a smoke test can see exactly where a drag
started and ended.

Both pointer and scroll output need the same Accessibility permission as the
keyboard, and it is re-read per event: revoking it mid-motion stops the cursor
rather than latching it.

Set Wispr Flow's toggle shortcut to Ctrl-S for the starter R3 mapping. The
bridge keeps Ctrl-S down for the duration of the physical click, avoiding the
zero-duration tap that some global-shortcut listeners miss. If you prefer
press-to-talk, add a `hold` binding to a non-trigger control and set Wispr Flow
to the same chord. Any unique chord built from `control`, `option`, `shift`, and
`command` plus one key works; `fn` cannot be emitted synthetically and is
rejected with an explanation.

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
unknown binding kind, unparseable shortcut, or out-of-range navigation value is
refused with a message instead of being silently ignored, so a typo cannot
quietly disable a binding or hand the cursor an absurd speed. Use
`--profile <path>` to load a profile from another location.

A binding's `kind` is `hold`, `repeat`, `tap`, or `tapSequence`. `repeat` is for
one-key editing/navigation bindings that should fire once and then repeat while
held. A `tapSequence` lists its shortcuts in order, separated by commas —
`"keys": "control+b, n"` — and an empty list is refused rather than accepted as
a binding that does nothing.

Schema version 2 adds the `navigation` section, and version 3 adds `repeat`
bindings. Version 1 and 2 profiles still load, so upgrading the bridge never
invalidates a mapping you already tuned. Inside `navigation` every field is
optional, so an experiment can be two lines:

```json
{
  "schemaVersion": 3,
  "name": "slower-pointer",
  "bindings": { "cross": { "kind": "tap", "keys": "return" } },
  "navigation": { "pointer": { "speed": 400 } }
}
```

`doctor` and `run` both print the navigation values actually in effect, which is
how you confirm the file you edited is the file being used.

## Development

```sh
swift test
swift build
```

Behavior is tested through a fake input source, a fake keyboard sink, and a fake
pointer sink, so press/release ordering, duplicate and out-of-order events,
held-key and held-button cleanup on disconnect and shutdown, per-controller hold
ownership, drag-versus-move event selection, deadzone/clamp/curve arithmetic,
continuous motion from a held stick, and the Accessibility refusal path all run
without a controller attached. The navigation engine takes its clock as an
argument, so a test advances time by hand and asserts exact pixel deltas.

Hardware checks live in
[docs/smoke/s1-controller-wispr.md](docs/smoke/s1-controller-wispr.md) and
[docs/smoke/s4-stick-navigation.md](docs/smoke/s4-stick-navigation.md). Do not
paste real session output or credentials into issues, fixtures, or logs.

## License

MIT. See [LICENSE](LICENSE).
