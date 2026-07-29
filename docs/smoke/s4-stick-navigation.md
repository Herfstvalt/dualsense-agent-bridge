# S4 manual smoke and tuning checklist — stick navigation

Automated tests cover the deadzone, the clamp, the response curve, continuous
motion from a held stick, release, disconnect, shutdown, profile decoding, and
the Accessibility refusal path with a fake axis source and a fake pointer sink.
They cannot prove that a real DualSense reports its sticks, that macOS accepts
the synthetic pointer events, or — the part that matters most here — that the
defaults *feel* right. This checklist covers exactly that gap.

Run it on a macOS 13+ machine with the controller paired. Record the date, the
macOS version, and pass/fail per step in the results table. Do not paste real
terminal output, transcripts, credentials, or absolute home paths into the
results.

Run the bridge from a logged-in GUI session (a terminal window, or a tmux window
inside one). A plain SSH audit session does not reliably receive controller HID
input, which is the failure mode already recorded for S1.

## Prerequisites

- [ ] Everything in [s1-controller-wispr.md](s1-controller-wispr.md) section 0
      still passes, so buttons are known good before sticks are judged.
- [ ] Accessibility permission granted to the terminal app that will run the
      bridge. Pointer output needs the same grant as keyboard output.
- [ ] A scratch window to point at — a text editor or a browser — and a scrollable
      view such as a long terminal buffer. Do not tune against a session doing
      real work.

## 0. Baseline without hardware

- [ ] `swift test` passes.
- [ ] `swift build -c release` succeeds with no warnings.
- [ ] `dualsense-bridge doctor` prints a `Navigation:` block showing both sticks,
      their deadzone, curve, and speed, plus the tick rate and stall clamp.
- [ ] `dualsense-bridge profile --starter` contains a `navigation` section and
      `"schemaVersion": 2`.
- [ ] An existing S1 profile (no `navigation` key, `"schemaVersion": 1`) still
      loads: `dualsense-bridge doctor --profile <old file>` reports it and shows
      the default navigation values.
- [ ] `dualsense-bridge profile --starter` shows `r3` on `control+s`, the three
      `tapSequence` bindings for `r1`/`l1`/`l3`, `touchpadButton` on
      `control+grave`, and no `r2` binding.
- [ ] Feeding that same output back in with `--profile` loads cleanly, which is
      what proves the sequence and arrow-key spellings can be read back.

## 1. Stick recognition

Start `dualsense-bridge run --dry-run` and keep its terminal **not** frontmost.

- [ ] `Background controller events: enabled` is printed. If it says `DISABLED`,
      stop: sticks will report nothing.
- [ ] Push the right stick. Periodic `mouse dx=… dy=…` summary lines appear.
- [ ] Push the left stick. Periodic `scroll dx=… dy=…` summary lines appear.
- [ ] Release both sticks. Summary lines stop within about a second and no
      further lines appear while the sticks are at rest.
- [ ] Confirm the output is *summaries*, not one line per tick: a one-second push
      should produce a small number of lines, not a hundred.
- [ ] Press Cross and L2 while a stick is held. Button lines appear interleaved
      with motion summaries; neither starves the other.

## 2. Pointer direction and feel

Run `dualsense-bridge run` (not dry-run) with focus on a scratch window.

- [ ] Right stick up moves the cursor up; down moves it down; left and right
      match. If any axis is backwards, set `pointer.invertX` or
      `pointer.invertY` and confirm the fix needs no rebuild.
- [ ] A diagonal push moves at the same speed as a straight push, not faster.
- [ ] A small push moves the cursor slowly and controllably; full deflection
      crosses the screen at a comfortable rate. Record the `speed` and
      `responseExponent` that felt right.
- [ ] Releasing the stick stops the cursor immediately, with no glide or
      overshoot.
- [ ] An untouched controller left alone for a minute does not drift the cursor.
      If it drifts, raise `pointer.deadzone` and record the value.
- [ ] Push the stick hard into a screen edge for several seconds, then release.
      The cursor stays visible on a display and can still be moved back with the
      stick and with the trackpad.
- [ ] With more than one display attached, drive the cursor between displays and
      into any gap between differently sized screens. It always stays somewhere
      visible.

## 3. Scroll direction and feel

With focus in a long terminal buffer or a web page:

- [ ] Left stick up scrolls up and down scrolls down. If reversed, set
      `scroll.invertY`.
- [ ] Left stick left and right scroll horizontally where the view supports it.
      If reversed, set `scroll.invertX`.
- [ ] Scrolling is smooth rather than stepped, and a small push scrolls slowly.
- [ ] Releasing stops scrolling immediately; there is no inertia.
- [ ] Scrolling a terminal does **not** insert or delete any text. Check the
      prompt is byte-for-byte unchanged afterwards.

## 4. Coexistence with the S1 bindings

- [ ] Hold L2 to dictate while moving the right stick. Dictation continues and
      the cursor moves; releasing L2 inserts the transcript as usual.
- [ ] Press Cross while a stick is held. Return is delivered once and motion is
      unaffected.
- [ ] Click the right stick (R3) while pushing it. Ctrl-S is delivered and the
      cursor keeps moving; R3 does not become a mouse click.
- [ ] Press R1, L1, and L3 in a tmux session. R1 moves to the next window, L1 to
      the previous, and L3 opens the session list. Confirm no literal `b`
      character is left on the prompt, which is what a chord instead of a
      sequence would produce.
- [ ] Press D-pad Up and Down at a shell prompt. History moves one entry per
      press.
- [ ] Press the touchpad button. Control-backtick reaches the focused app.
- [ ] Left and middle click are still unbound, so nothing in this bridge can
      left-click or left-drag.

## 4b. Right button hold and drag (R2)

- [ ] Pull R2 with the pointer over a Finder window or web page. A context menu
      opens on release, exactly as a real right click would.
- [ ] Hold R2 and push the right stick. `run --dry-run` reports `right button
      down`, then `drag dx=… dy=…` summaries instead of `mouse dx=… dy=…`, then
      `right button up`. Button lines are not throttled.
- [ ] Release R2 without moving. The button lifts and the next stick push reports
      `mouse`, not `drag`, again.
- [ ] Hold R2, push the stick, let the stick return to centre, then push again
      while still holding R2. The button stays down across the pause.
- [ ] Press R2 twice without releasing, then release twice. Only one `right
      button down` and one `right button up` appear.
- [ ] Confirm this is a *right*-button drag only: it drives context menus and any
      right-drag gesture the focused app implements. It is not text selection,
      which macOS does with a left-button drag.
- [ ] Confirm no key output accompanies R2. `run --dry-run` shows no
      `unmapped(r2)` line and no keystroke.

## 5. Interruption and cleanup

- [ ] While holding a stick, turn the controller off. Motion stops at once and
      the cursor stays where it was.
- [ ] While holding a stick, press Control-C in the bridge terminal. It prints
      `Stopped; all synthetic keys released and motion stopped.` and the cursor
      stops.
- [ ] While holding a stick, `kill` the bridge process. Motion stops.
- [ ] Reconnect the controller and confirm sticks work again with no inherited
      motion from the previous session.
- [ ] While holding a stick, revoke Accessibility permission. Motion stops, the
      bridge logs one `navigation refused: …` line rather than one per tick, and
      the cursor is not left drifting.
- [ ] Suspend the bridge (`Control-Z`, wait ten seconds, `fg`) while a stick is
      held. On resume the cursor moves at most a small jump, not across the whole
      screen; this is the stall clamp doing its job.
- [ ] While holding R2, turn the controller off. The right button comes back up:
      confirm a subsequent physical left click behaves normally and no context
      menu is stuck open.
- [ ] While holding R2, press Control-C in the bridge terminal. The button is
      released on the way out.
- [ ] While holding R2, revoke Accessibility permission, then stop the bridge.
      The button is still released — cleanup deliberately bypasses the permission
      check so a revoked permission cannot latch it.
- [ ] While holding R2, `kill` the bridge process. Confirm the button does not
      stay down.

## 6. Configuration

- [ ] Change `pointer.speed` in the profile, restart, and confirm `run` prints
      the new value and the feel changes with no rebuild.
- [ ] Set a deliberately invalid value (`"deadzone": 0.99`) and confirm
      `dualsense-bridge doctor --profile <path>` refuses it and names both the
      field and the accepted range.
- [ ] Record the final tuned values so they can become the defaults if they beat
      the shipped ones.

## Results

| Section | Status | Notes |
| --- | --- | --- |
| 0. Baseline without hardware | pass | Clean-scratch `swift test` (262 tests, 20 suites) and a clean-scratch release build pass with no warnings; `doctor`, `profile --starter`, and a version 1 profile without a `navigation` section were all verified. |
| 1. Stick recognition | pending | Needs the paired DualSense in a GUI session. |
| 2. Pointer direction and feel | pending | Subjective; the shipped defaults are a starting point, not a verdict. |
| 3. Scroll direction and feel | pending | Horizontal wheel polarity in particular needs a real check; `scroll.invertX` exists for exactly that. |
| 4. Coexistence with the S1 bindings | pending | Automated coverage exists for stick-and-button coexistence; the live Wispr path does not. |
| 5. Interruption and cleanup | pending | Automated coverage exists for held-key and held-button release, disconnect, reconnect, profile replacement, shutdown, deinit, and permission-refusal paths. |
| 6. Configuration | pending | Profile decoding and validation are covered by automated tests; the live feel of a changed value is not. |

### Tuning record

Fill this in during the hardware pass so the numbers survive the session.

| Setting | Shipped default | Tried | Kept |
| --- | --- | --- | --- |
| `pointer.deadzone` | 0.15 | | |
| `pointer.responseExponent` | 2.0 | | |
| `pointer.speed` | 700 | | |
| `scroll.deadzone` | 0.2 | | |
| `scroll.responseExponent` | 2.0 | | |
| `scroll.speed` | 500 | | |
| `tickInterval` | 0.008 | | |

Sections 1 through 6 are the human-in-the-loop part of this slice and are
expected to be executed on the user's Mac with the controller paired.
