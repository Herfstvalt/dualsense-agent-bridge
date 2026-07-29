# DualSense Agent Bridge — Product Requirements

## Problem Statement

Terminal coding sessions are powerful but awkward to operate when the user is
away from the keyboard. Codex, Claude Code, and other agents may be spread
across local and SSH-backed tmux sessions, while voice input lives in a
separate application such as Wispr Flow. The user wants a small, dependable
macOS bridge that makes a DualSense controller a deliberate command surface:
start and stop dictation, send or cancel a message, interrupt a running agent,
move between teamwork sessions, navigate output, and hear the latest response.

The bridge must remain predictable. A normal Enter action must not accidentally
kill a session, a controller disconnect must not leave a key held down, and
spoken output must not leak credentials or raw private logs.

## Solution

Build a macOS-first, open-source Swift application with a CLI/daemon core. It
normalizes DualSense input events into configurable actions, emits the
keyboard/mouse events required by Wispr Flow and terminal applications, and
delegates session operations to a small tmux-backed Session Bridge. A local
speech adapter reads a sanitized, bounded latest response with macOS `say`.

The first release uses GameController for ordinary DualSense controls and a
small platform boundary for optional raw-HID controls such as the controller
mic button. It starts with deterministic fake-input and command-runner tests,
then adds a documented live hardware smoke test on the user's Mac.

## User Stories

1. As a terminal-based agent user, I want to pair a DualSense controller and
   see its connection state, so that I know whether input will be accepted.
2. As a terminal-based agent user, I want to choose a controller profile, so
   that the same hardware can have safe mappings for different workflows.
3. As a Wispr Flow user, I want to hold a dedicated controller button to start
   press-to-talk, so that I can dictate without reaching for the keyboard.
4. As a Wispr Flow user, I want releasing that button to stop press-to-talk,
   so that recording does not continue unexpectedly.
5. As a Wispr Flow user, I want an optional hands-free toggle, so that longer
   thoughts do not require holding a button.
6. As a terminal user, I want Cross to emit Enter, so that a dictated message
   can be sent immediately.
7. As a terminal user, I want Circle to emit Escape, so that I can cancel a
   dictation or close a transient prompt.
8. As an agent operator, I want a dedicated interrupt action, so that R3 can
   send Ctrl-C without confusing it with message submission.
9. As an agent operator, I want to list active tmux sessions, so that I can
   understand the current teamwork workspace.
10. As an agent operator, I want D-pad left/right to change the selected
    session, so that switching agents is quick and deterministic.
11. As an agent operator, I want an explicit session picker, so that a long
    list of sessions remains navigable.
12. As an agent operator, I want the bridge to focus or attach the selected
    terminal target, so that controller actions reach the intended session.
13. As an agent operator, I want a safe send-text command for the selected
    target, so that non-voice shortcuts can still be automated.
14. As an agent operator, I want local and SSH-backed tmux targets represented
    consistently, so that the same controls work across machines.
15. As an agent operator, I want to capture the latest visible response, so
    that I can review what the selected agent said without scrolling manually.
16. As an agent operator, I want the latest response spoken aloud, so that I
    can listen while keeping my hands on the controller.
17. As a privacy-conscious user, I want secrets and sensitive terminal noise
    redacted or bounded before speech, so that TTS does not expose credentials.
18. As a controller user, I want the right stick to act as a mouse and the
    left stick/D-pad to scroll or navigate, so that I can roam through output.
19. As a controller user, I want deadzones, repeat rates, and mappings to be
    configurable, so that the controls feel natural on my hardware.
20. As a user with multiple terminal applications, I want app-aware profiles,
    so that a key can mean Enter in a terminal but something else elsewhere.
21. As a macOS user, I want clear Accessibility and microphone permission
    guidance, so that setup failures are understandable.
22. As a safety-conscious user, I want destructive actions to require a
    long-hold or chord and confirmation, so that an accidental press cannot
    kill a session.
23. As a developer, I want fake controller events and fake command runners, so
    that core behavior can be tested without a physical controller or live
    tmux workspace.
24. As a maintainer, I want provider-specific transcript readers behind an
    adapter boundary, so that Codex and Claude log formats can evolve without
    changing controller mappings.
25. As a maintainer, I want the project to be MIT-licensed and documented, so
    that other users can safely extend it.

## Implementation Decisions

- Use Swift Package Manager and target macOS 13 or newer.
- Keep a CLI/daemon core as the first user-facing surface; a menu-bar shell is
  a later presentation layer over the same core.
- Normalize hardware input into a small event model containing controller
  identity, control, phase (pressed/released/repeated), timestamp, and source.
- Keep mapping, layers, chords, hold behavior, and safety confirmation in a
  pure action router with no direct AppKit or tmux dependencies.
- Use GameController for ordinary DualSense buttons, axes, and touchpad input
  where available. Isolate raw HID parsing for the mic button and future
  controller-audio support behind a platform adapter.
- Emit Wispr Flow's user-configured keyboard shortcut as a key-down/key-up
  pair for press-to-talk. Do not depend on private Wispr APIs or UI automation.
- Treat the physical DualSense mic button as independently configurable; the
  default profile may reserve it for hardware mute while a separate button
  controls Wispr.
- Use Cross→Enter, Circle→Escape, and R3→Ctrl-C in the starter terminal
  profile. A literal session kill is never bound to a normal Enter action.
- Make tmux the canonical local control plane. The Session Bridge exposes
  list, select, focus/attach, send, interrupt, capture, and latest-response
  operations through typed interfaces.
- Represent remote SSH targets as an explicit target kind; do not silently
  execute commands on an unintended host.
- Capture terminal output through a narrow adapter. Start with tmux capture;
  add Codex and Claude JSONL readers as separate provider adapters.
- Sanitize, redact, and cap output before passing it to `say`. Speech is local
  by default and never uploads transcripts.
- Store user mappings in a versioned local configuration file. Never commit
  real paths, tokens, transcripts, or credentials.
- Require explicit Accessibility permission before synthetic input begins and
  expose actionable diagnostics when it is missing.

## Required Completion Criteria

### Tracking setup

- [x] Public repository, license, README, and contribution boundaries exist.
- [x] Parent PRD is published and child slices are linked.
- [x] Issue labels and slice statuses are initialized for the five child slices.

### Backend completion

- [ ] Normalized controller event and action-router contracts are implemented.
- [ ] Wispr press-to-talk and terminal keyboard actions are implemented.
- [ ] Session Bridge supports local tmux list/select/send/interrupt/capture.
- [ ] Configuration is versioned, validated, and safe by default.
- [ ] Provider transcript adapters have bounded, testable interfaces.

### UI completion

- [ ] CLI diagnostics expose controller, permissions, profile, and target state.
- [ ] A usable session picker exists for the initial release.
- [ ] Mouse/scroll behavior and feedback are configurable.
- [ ] A menu-bar shell is either implemented or explicitly deferred.

### Integration/smoke completion

- [ ] Fake-input integration tests cover press/release, chords, disconnect, and
  held-key cleanup.
- [ ] tmux integration tests use an isolated temporary server/session.
- [ ] macOS hardware smoke test passes with a paired DualSense.
- [ ] Wispr Flow PTT and Cross→Enter are verified in a real terminal.
- [ ] TTS output is verified with redaction and length limits.

### End-to-end user acceptance

- [ ] User can launch the bridge, select a teamwork session, dictate a prompt,
  send it, interrupt safely, switch sessions, and hear the latest response.
- [ ] Disconnecting or quitting the bridge releases all synthetic keys/buttons.
- [ ] No credentials or raw private session output are written to repository
  artifacts or diagnostic logs.

## Implementation Slices

### S1 — Controller-to-terminal and Wispr tracer bullet

Owner lane: `backend-engineering`, `integration`

Deliver a complete path from normalized controller events to Wispr PTT and
terminal actions: dedicated hold-to-talk, Cross→Enter, Circle→Escape, R3→
Ctrl-C, configuration, fake-input tests, and a documented live smoke checklist.

Suggested labels: `enhancement`, `needs-triage`, `backend-engineering`,
`integration`, `human-in-the-loop`

Status: Created in #2; PR / merge commit to be recorded.

### S2 — tmux teamwork session bridge

Owner lane: `backend-engineering`, `integration`

Expose safe list/select/focus/send/interrupt operations for local tmux and a
target abstraction that can later support SSH. Include isolated tmux tests and
session-switch actions.

Suggested labels: `enhancement`, `needs-triage`, `backend-engineering`,
`integration`

Status: Created in #3; PR / merge commit to be recorded.

### S3 — Latest-response capture and local speech

Owner lane: `backend-engineering`

Capture the selected target's latest response, strip terminal noise, redact
common secrets, cap length, and speak it with a replaceable local speech
adapter. Add provider-reader seams without coupling the controller layer.

Suggested labels: `enhancement`, `needs-triage`, `backend-engineering`

Status: Created in #4; PR / merge commit to be recorded.

### S4 — Stick navigation and profile ergonomics

Owner lane: `ui/ux`, `backend-engineering`

Add right-stick mouse, left-stick/D-pad scrolling, deadzones, repeat behavior,
layers/profiles, feedback, and safe configuration diagnostics.

Suggested labels: `enhancement`, `needs-triage`, `ui/ux`,
`human-in-the-loop`

Status: Created in #5; PR / merge commit to be recorded.

Deferred out of the first S4 implementation, deliberately rather than by
omission:

- **Profile and layer switching from the controller.** Navigation settings are
  persisted and validated in the profile, and a profile swap already stops all
  motion safely, but there is no controller-driven layer stack and no binding
  that changes profiles at runtime. Choosing how layers compose is a design
  question that physical tuning should answer first.
- **D-pad scrolling.** The D-pad is reported as four buttons and can be bound to
  any shortcut today. Repeat-rate scrolling from the D-pad would need its own
  repeat engine and would duplicate what the left stick already does better.
- **Stick role swapping.** The right stick is the pointer and the left stick
  scrolls; every other knob is configurable. Swapping roles is a one-line change
  to `NavigationSettings.role(of:)` when someone actually wants it.
- **Mouse click remapping.** No stick or button emits mouse buttons, so nothing
  in this slice can click, drag, or select by accident.

### S5 — Launch shell and end-to-end release smoke

Owner lane: `integration`, `ui/ux`

Provide a polished launch path (CLI first, menu-bar optional), permission
guidance, launch-at-login documentation, and a full local/SSH end-to-end smoke
run. Record any explicitly deferred hardware-audio work.

Suggested labels: `enhancement`, `needs-triage`, `integration`, `ui/ux`,
`human-in-the-loop`

Status: Created in #6; PR / merge commit to be recorded.

## Testing Decisions

- Test observable behavior through normalized events, emitted actions, command
  results, and user-facing diagnostics rather than private implementation
  details.
- Use focused unit tests for pure mapping, safety, redaction, and parsing
  logic; use integration tests for the Session Bridge and synthetic event
  boundary; use one end-to-end smoke path for the real controller and Wispr.
- Use an isolated tmux server and temporary sessions in automated tests.
- Add regression tests for held-key cleanup on disconnect and for command-target
  validation before destructive operations.
- Keep live hardware, microphone, Accessibility, and TTS checks documented and
  repeatable rather than pretending they can be fully simulated.

## Out of Scope

- Reimplementing Wispr Flow or calling undocumented Wispr services.
- Direct private APIs for Codex or Claude Code sessions.
- Cloud transcript storage, remote speech synthesis, or telemetry by default.
- Automatic destructive session killing from a single normal button press.
- Controller audio over Bluetooth in the first milestone.
- Supporting Windows, Linux, console gameplay, or arbitrary gamepad brands in
  the first release.
- A full terminal emulator or replacement for tmux.

## Further Notes

The first coding lane should land S1 as a tracer bullet. Once it is tested on
the user's machine, S2 and S3 can proceed with confidence because the action
router and safety boundaries will already be exercised. A realistic estimate is
one focused session for the S1 prototype, two to four days for a usable local
MVP, and roughly one additional week for polish, remote targets, provider
adapters, and repeatable hardware smoke coverage.
