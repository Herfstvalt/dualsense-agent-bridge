## Parent

#1

## What to build

Add a latest-response pipeline for the selected Session Bridge target. It
should choose the best available capture source, remove terminal noise,
redact common secrets, cap speech length, and read the result locally through
a replaceable speech adapter. Bind the read action to a controller control.

This is an AFK slice after S2.

## Acceptance criteria

- [ ] A public capture interface returns the latest assistant/agent response
      without exposing provider-specific log formats to controller code.
- [ ] ANSI/control noise, progress spinners, and obvious credential patterns
      are excluded or replaced before speech.
- [ ] Speech input is bounded by a documented character/time limit.
- [ ] The default speech adapter invokes macOS `say` locally and reports
      failures without crashing the bridge.
- [ ] A fake speech adapter makes the full behavior integration-testable.
- [ ] Tests cover redaction, empty output, truncation, and adapter failure.
- [ ] A controller action reads the selected target and never reads a
      different session due to stale selection state.

## Completion

- PR:
- Merge commit:
- Tests:
- Deferred:

## Blocked by

- #3

