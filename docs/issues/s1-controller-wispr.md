## Parent

#1

## What to build

Deliver the first complete path from a normalized DualSense event to a
terminal-safe action and Wispr Flow press-to-talk. The starter profile must
support a dedicated hold-to-talk control, Cross→Enter, Circle→Escape, and
R3→Ctrl-C, with a fake-input harness and a concise live hardware checklist.

This is a HITL slice because the implementation can be automated, but final
acceptance requires a paired DualSense, Accessibility permission, and a real
terminal/Wispr Flow smoke test.

> Mapping history: this issue records the original S1 tracer, where R3 sent
> Ctrl-C. The active starter profile was deliberately superseded during S4:
> R3 now sends the user's Ctrl-S Wispr Flow toggle. The current hardware checks
> are in `docs/smoke/s4-stick-navigation.md`.

## Acceptance criteria

- [ ] A controller event model represents control, press/release phase, and
      disconnect without leaking framework types into the action router.
- [ ] A configurable dedicated control emits the Wispr shortcut on press and
      releases it on button-up; the default shortcut is documented and can be
      changed without recompiling.
- [ ] Cross emits Return, Circle emits Escape, and R3 emits Ctrl-C to the
      configured keyboard sink.
- [ ] Disconnect and shutdown release every synthetic key that is currently
      held, including the Wispr shortcut.
- [ ] Fake-input tests cover press/release ordering, duplicate events, and
      held-key cleanup.
- [ ] Accessibility diagnostics explain how to grant permission and refuse to
      emit synthetic events when permission is unavailable.
- [ ] A manual smoke checklist verifies a real DualSense button, Wispr Flow
      dictation, Cross→Enter, Circle cancellation, and R3 interruption.

## Completion

- PR:
- Merge commit:
- Tests:
- Deferred:

## Blocked by

None - can start immediately.
