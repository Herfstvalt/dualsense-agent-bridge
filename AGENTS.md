# DualSense Agent Bridge

## Scope

This repository contains a macOS bridge that turns DualSense controller input
into safe terminal, Wispr Flow, tmux, and local text-to-speech actions.

## Engineering expectations

- Keep platform integration behind small, testable interfaces.
- Prefer vertical behavior tests over implementation-detail tests.
- Use TDD for new behavior when practical: red, green, refactor.
- Never commit credentials, transcripts, private session output, or machine-
  specific paths.
- Treat interrupt/kill/send actions as safety-sensitive; require explicit
  confirmation for destructive operations.
- Keep source and test files focused and roughly below 500 lines.

## Validation

Run `swift test` for package behavior. Hardware checks are manual smoke tests
on a macOS machine with a paired DualSense and Accessibility permission.

