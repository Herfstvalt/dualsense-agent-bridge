# S1 manual smoke checklist — controller to Wispr and terminal actions

Automated tests cover the event model, the action router, held-key cleanup, and
the Accessibility refusal path with a fake input source and a fake keyboard
sink. They cannot prove that macOS accepts the synthetic events, that a real
DualSense reports the expected controls, or that Wispr Flow recognizes the
shortcut. This checklist covers exactly that gap.

Run it on a macOS 13+ machine. Record the date, the macOS version, and
pass/fail per step in the results table. Do not paste real terminal output,
transcripts, credentials, or absolute home paths into the results.

## Prerequisites

- [ ] A DualSense controller paired over Bluetooth or connected by USB.
- [ ] Wispr Flow installed and running, with its dictation shortcut set to the
      same keys as the `hold` binding reported by `dualsense-bridge doctor`
      (starter profile: `control+option+space`).
- [ ] Accessibility permission granted to the terminal app that will run the
      bridge (System Settings > Privacy & Security > Accessibility).
- [ ] A scratch directory and a long-running command available for the
      interrupt test. Never smoke-test against a session doing real work.

## 0. Baseline without hardware

- [ ] `swift test` passes.
- [ ] `swift build` succeeds.
- [ ] `dualsense-bridge doctor` reports the profile, the binding list, and the
      Accessibility state.
- [ ] `dualsense-bridge run --dry-run` starts, prints the binding summary, and
      exits on Control-C with `Stopped; all synthetic keys released.`

## 1. Permission boundary

- [ ] Revoke Accessibility for the host terminal, then run
      `dualsense-bridge run`. It refuses to start, prints the numbered
      remediation steps, and emits nothing.
- [ ] Re-grant permission, relaunch the terminal, and confirm
      `dualsense-bridge doctor` now reports permission as granted.

## 2. Controller recognition

- [ ] Start `dualsense-bridge run --dry-run` and connect the controller.
      A `connected` line appears.
- [ ] Press each bound control once and confirm the printed control name
      matches the physical button: `cross`, `circle`, `r3`, and the hold
      control (`l2` in the starter profile).
- [ ] Confirm the DualSense mic button produces no binding output; it should
      keep its hardware mute behavior.

## 3. Wispr Flow press-to-talk

Run `dualsense-bridge run` (not dry-run) with focus in a text field.

- [ ] Hold the hold control. Wispr Flow starts dictating.
- [ ] Speak a short phrase and keep holding. Dictation continues.
- [ ] Release the control. Wispr Flow stops dictating and the transcript is
      inserted. Recording does not continue after release.
- [ ] Repeat three times in quick succession. No stuck modifier: typing a
      normal character afterwards produces that character, not a shortcut.

## 4. Terminal actions

With focus in a real terminal running an interactive agent session:

- [ ] Dictate a short prompt with the hold control, then press Cross. The
      message is submitted, exactly as pressing Return would.
- [ ] Start a new dictation and press Circle. The dictation/prompt is
      cancelled, matching Escape.
- [ ] Start a long-running command, then click the right stick (R3). The
      command is interrupted, matching Control-C. No session is killed and no
      other window is affected.

## 5. Interruption and cleanup

- [ ] While holding the hold control, turn the controller off (or unplug it).
      The bridge logs a disconnect and the held shortcut is released: Wispr
      Flow stops and no modifier stays latched.
- [ ] While holding the hold control, press Control-C in the bridge terminal.
      The bridge shuts down and reports that all synthetic keys were released.
- [ ] While holding the hold control, `kill` the bridge process. Same result.
- [ ] After each of the three cases, type in a normal text field and confirm
      plain characters appear, proving no modifier is stuck.
- [ ] Reconnect the controller and confirm input works again without a stuck
      hold from the previous session.

## 6. Configuration

- [ ] `dualsense-bridge profile > ~/.config/dualsense-bridge/profile.json`,
      change the hold shortcut to a different unique chord, change the same
      shortcut in Wispr Flow, and confirm press-to-talk still works with no
      rebuild.
- [ ] Put a deliberate typo in the profile (for example `kind: "toggle"`) and
      confirm `dualsense-bridge doctor --profile <path>` refuses it and names
      the problem.

## Results

| Section | Status | Notes |
| --- | --- | --- |
| 0. Baseline without hardware | pass | `swift test` (97 tests) and `swift build` pass; `doctor`, `profile`, `controls`, and `run --dry-run` verified, including clean shutdown on signal. |
| 1. Permission boundary | pending | Needs a machine where Accessibility can be toggled for the host terminal. |
| 2. Controller recognition | pending | No DualSense connected in the implementation environment. |
| 3. Wispr Flow press-to-talk | pending | Wispr Flow not installed in the implementation environment. |
| 4. Terminal actions | pending | Requires a connected controller. |
| 5. Interruption and cleanup | pending | Requires a connected controller; automated coverage exists for disconnect and shutdown release. |
| 6. Configuration | pending | Profile validation is covered by automated tests; the live Wispr shortcut change is not. |

Sections 1 through 6 are the human-in-the-loop part of this slice and are
expected to be executed on the user's Mac with the controller paired.
