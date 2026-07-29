## Parent

#1

## What to build

Make navigation comfortable for repeated use. Add right-stick mouse motion,
left-stick/D-pad scroll behavior, deadzones, acceleration/repeat settings,
profile/layer selection, and visible diagnostics for the active mapping.

This is a HITL slice because the final tuning is subjective and must be
validated on a real DualSense.

## Acceptance criteria

- [ ] Right-stick motion maps to bounded mouse deltas with a configurable
      deadzone and response curve.
- [ ] Left-stick or D-pad navigation maps to scroll events without starving
      button actions.
- [ ] Profile and layer changes are explicit, persisted, and observable in
      diagnostics.
- [ ] Stick release stops mouse/scroll output immediately.
- [ ] Fake-axis tests cover deadzone, clamp, response curve, and disconnect.
- [ ] Manual smoke checklist records a comfortable mapping on the user's Mac
      without changing terminal text accidentally.

## Completion

- PR: #8 (stacked on `agent/s1-controller-wispr`, PR #7)
- Merge commit:
- Tests: `swift test` — 275 tests in 22 suites, plus a clean-scratch
  release build with no warnings. Coverage includes normalized stick axes,
  deadzone, clamp, response curve, continuous motion, release, disconnect,
  shutdown, sub-pixel quantization, the Accessibility refusal path, throttled
  dry-run logging, version 1 and version 2 profile decoding, ordered tmux key
  sequences, starter-profile round trips, R2-left/L2-right ownership, drag,
  failure and cleanup behavior, plus one-finger touchpad pointer motion and
  two-finger scrolling.
- Deferred: controller-driven profile/layer switching, D-pad repeat scrolling,
  stick role swapping, configurable middle/arbitrary mouse buttons, and
  system-level three-/four-finger gestures — each recorded with its reason under
  S4 in `docs/prd.md`. R2 and L2 now have fixed, safe left/right holds. The
  subjective tuning pass and sections 1 through 6 of
  `docs/smoke/s4-stick-navigation.md` still need the user's Mac.

## Blocked by

- #2
