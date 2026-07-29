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

- PR:
- Merge commit:
- Tests:
- Deferred:

## Blocked by

- #2

