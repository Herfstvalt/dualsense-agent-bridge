## Parent

#1

## What to build

Package the working bridge as a clean launchable macOS tool, with CLI
diagnostics, permission guidance, optional menu-bar presentation, and a
repeatable end-to-end smoke path across controller input, Wispr Flow, tmux,
session switching, and latest-response speech. Document what remains deferred.

This is a HITL release slice.

## Acceptance criteria

- [ ] A fresh clone can build and run the documented command without hidden
      machine-specific setup.
- [ ] Diagnostics report controller connection, Accessibility status, Wispr
      shortcut configuration, tmux availability, and selected target.
- [ ] The end-to-end smoke checklist is executable on a clean macOS account
      after granting the documented permissions.
- [ ] Shutdown and controller disconnect leave no stuck synthetic input.
- [ ] Logs and support output exclude credentials and raw private transcripts.
- [ ] Launch-at-login and menu-bar behavior are either implemented and tested
      or explicitly marked deferred in the README and PRD.
- [ ] Repository quality gates pass: tests, formatting, documentation, and a
      clean working tree.

## Completion

- PR:
- Merge commit:
- Tests:
- Deferred:

## Blocked by

- #2
- #3
- #4
- #5

