## Parent

#1

## What to build

Add a Session Bridge that makes local tmux sessions a typed, safe target for
controller actions. The bridge must list sessions, select a target, focus or
attach it, send text, interrupt it, and capture visible output. Wire D-pad
left/right and the existing interrupt/send actions through the same public
interface used by S1.

This is an AFK slice once S1's action contract is merged.

## Acceptance criteria

- [ ] The Session Bridge lists session identity, window/pane target, attached
      state, and a stable display label.
- [ ] Selection changes are deterministic and wrap or clamp according to a
      documented policy.
- [ ] Send and interrupt validate the selected target before invoking tmux.
- [ ] Capture returns bounded output with terminal control sequences removed.
- [ ] D-pad left/right switch the selected target without changing unrelated
      mappings.
- [ ] An isolated temporary tmux server/session integration test covers list,
      select, send, interrupt, and capture.
- [ ] The design leaves an explicit target boundary for future SSH sessions;
      no command can silently jump to a different host.

## Completion

- PR:
- Merge commit:
- Tests:
- Deferred:

## Blocked by

- #2

