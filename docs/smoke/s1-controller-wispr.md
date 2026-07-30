# S1 manual smoke checklist — controller to Wispr and terminal actions

Automated tests cover the event model, the action router, held-key cleanup, and
the Accessibility refusal path with a fake input source and a fake keyboard
sink. They cannot prove that macOS accepts the synthetic events, that a real
DualSense reports the expected controls, or that Wispr Flow recognizes the
shortcut. This checklist covers exactly that gap.

The original S1 profile used R3 for Ctrl-C. The active starter profile now uses
R3 for the user's Ctrl-S Wispr Flow toggle; the complete current mapping and
hardware checks live in `s4-stick-navigation.md`. The steps below reflect that
current R3 behavior so they cannot accidentally interrupt a live command.

Run it on a macOS 13+ machine. Record the date, the macOS version, and
pass/fail per step in the results table. Do not paste real terminal output,
transcripts, credentials, or absolute home paths into the results.

## Prerequisites

- [ ] A DualSense controller paired over Bluetooth or connected by USB.
- [ ] Wispr Flow installed and running, with its toggle shortcut set to Ctrl-S
      for the active starter profile. To smoke-test press-to-talk as well, use a
      custom profile that assigns `hold control+option+space` to an unreserved
      control and configure Wispr Flow to the same chord.
- [ ] Accessibility permission granted to the terminal app that will run the
      bridge (System Settings > Privacy & Security > Accessibility).
- [ ] A scratch text field available for the dictation-toggle test. Never
      smoke-test synthetic input against a session doing real work.
- [ ] The bridge running in its own terminal inside the logged-in macOS GUI
      session, so focus can stay on the target session. Do not launch the bridge
      from a plain SSH login: it can discover the controller there but does not
      reliably receive HID input. The target terminal may itself be connected
      over SSH. Synthetic keys go to the focused window; if the bridge's
      terminal has focus, Cross and R3 act on that terminal instead.

## 0. Baseline without hardware

- [ ] `swift test` passes.
- [ ] `swift build` succeeds.
- [ ] `dualsense-bridge doctor` reports the profile, the binding list, the
      Accessibility state, and the controllers GameController currently sees.
      With the controller off it says none are connected; with the controller on
      it names it.
- [ ] `dualsense-bridge run --dry-run` starts, prints the binding summary, and
      exits on Control-C with `Stopped; all synthetic keys released.`

## 1. Permission boundary

- [ ] Revoke Accessibility for the host terminal, then run
      `dualsense-bridge run`. It refuses to start, prints the numbered
      remediation steps, and emits nothing.
- [ ] Re-grant permission, relaunch the terminal, and confirm
      `dualsense-bridge doctor` now reports permission as granted.

## 2. Controller recognition

- [x] Start `dualsense-bridge run --dry-run` and confirm it prints
      `Background controller events: enabled`. If it prints `DISABLED`, stop:
      the controller will connect and every press will be dropped, because
      macOS 11.3 and newer withhold controller input from processes that are
      not frontmost.
- [x] Connect the controller. A `connected` line appears.
- [ ] Press each bound control once and confirm the printed control name
      matches the physical button: Cross, Circle, Square, Triangle, R3, the
      shoulders, D-pad, touchpad click, R2, and L2. Do this while the bridge's own
      terminal is **not** frontmost, which is the way it will actually be used.
- [ ] Confirm the DualSense mic button produces no binding output; it should
      keep its hardware mute behavior.

## 3. Wispr Flow toggle and optional press-to-talk

Run `dualsense-bridge run` (not dry-run) with focus in a text field.

- [ ] Click R3 once (press and release). Wispr Flow starts dictating through its
      Ctrl-S toggle; the bridge holds the chord for the physical click.
- [ ] Speak a short phrase, then click R3 again. Dictation stops and the
      transcript is inserted.
- [ ] If a custom `hold` binding was prepared, hold it, speak, and release it.
      Wispr starts and stops on the physical edges with no stuck modifier.

## 4. Terminal actions

With focus in a real terminal running an interactive agent session:

- [ ] Dictate a short prompt with R3 (or a configured hold control), then press Cross. The
      message is submitted, exactly as pressing Return would.
- [ ] Start a new dictation and press Circle. The dictation/prompt is
      cancelled, matching Escape.
- [ ] Click the right stick (R3). Wispr Flow toggles dictation using Ctrl-S;
      click R3 again and confirm dictation stops. No command is interrupted and
      no other window is affected.
- [ ] Tap Square in a scratch prompt and confirm one character is removed. Hold
      Square and confirm Backspace begins repeating after about 400 ms, then
      stops immediately on release.

## 5. Interruption and cleanup

Cleanup is never gated on Accessibility permission, so these cases must hold
even if permission is revoked mid-hold.

- [ ] With a custom hold binding active, turn the controller off (or unplug it).
      The bridge logs a disconnect and the held shortcut is released: Wispr
      Flow stops and no modifier stays latched.
- [ ] While holding that custom control, press Control-C in the bridge terminal.
      The bridge shuts down and reports that all synthetic keys were released.
- [ ] While holding that custom control, `kill` the bridge process. Same result.
- [ ] After each of the three cases, type in a normal text field and confirm
      plain characters appear, proving no modifier is stuck.
- [ ] Reconnect the controller and confirm input works again without a stuck
      hold from the previous session.
- [ ] While holding that custom control, revoke Accessibility permission and then
      release the control. The key still comes up: typing afterwards produces
      plain characters.

## 6. Configuration

- [ ] Seed a profile safely, without redirecting onto the file the command may
      read:

      ```sh
      dualsense-bridge profile --starter > /tmp/dualsense-profile.json
      mkdir -p ~/.config/dualsense-bridge
      mv /tmp/dualsense-profile.json ~/.config/dualsense-bridge/profile.json
      ```

- [ ] Change the hold shortcut to a different unique chord, change the same
      shortcut in Wispr Flow, and confirm press-to-talk still works with no
      rebuild.
- [ ] Bind two controls to the same shortcut, hold both, release one, and
      confirm dictation continues until the second is released.
- [ ] Put a deliberate typo in the profile (for example `kind: "toggle"`) and
      confirm `dualsense-bridge doctor --profile <path>` refuses it and names
      the problem.

## Results

| Section | Status | Notes |
| --- | --- | --- |
| 0. Baseline without hardware | pass | `swift test` (282 tests, 23 suites) and `swift build -c release` pass; the starter profile exports R3 as `hold control+s`, Square as `repeat delete`, and the confirmed Command-Z/C/V shortcuts. |
| 1. Permission boundary | pending | Needs a machine where Accessibility can be toggled for the host terminal. |
| 2. Controller recognition | partial | A plain SSH launch discovered the controller but received no HID events. Re-running in the logged-in GUI session connected successfully and logged the bound buttons, including both physical edges of R3. The intentionally unbound mic button still needs a no-binding check. |
| 3. Wispr Flow press-to-talk | pending | Wispr Flow is installed and running on the hardware-test Mac; real shortcut activation and dictation remain unverified. |
| 4. Terminal actions | pending | Cross→Return and Circle→Escape passed in dry-run; real synthetic output and the current R3→Ctrl-S Wispr toggle remain unverified. |
| 5. Interruption and cleanup | pending | Requires a connected controller; automated coverage exists for disconnect and shutdown release. |
| 6. Configuration | pending | Profile validation is covered by automated tests; the live Wispr shortcut change is not. |

Sections 1 through 6 are the human-in-the-loop part of this slice and are
expected to be executed on the user's Mac with the controller paired.
