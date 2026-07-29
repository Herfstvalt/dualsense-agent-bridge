# DualSense Agent Bridge

Use a PlayStation 5 DualSense controller to drive terminal-based coding
sessions on macOS.

The project is intended to make Codex, Claude Code, and other tmux-backed
sessions usable from a controller plus Wispr Flow:

- a dedicated controller action starts/stops Wispr Flow press-to-talk;
- Cross sends Enter and Circle cancels;
- R3 interrupts the focused session with Ctrl-C;
- the D-pad changes the active tmux session;
- the sticks can become mouse/scroll controls;
- the latest safe response can be spoken locally with macOS `say`.

This is an early, macOS-first open-source project. The first milestone favors
an observable CLI/daemon and deterministic fake-input tests before adding a
menu-bar shell or provider-specific transcript parsers.

## Requirements

- macOS 13 or newer
- Swift 6 / Xcode command-line tools
- A paired DualSense controller (USB is recommended for controller-audio work)
- Accessibility permission for synthetic keyboard and mouse events
- Wispr Flow configured with a unique accepted keyboard shortcut
- tmux for session control

## Development

```sh
swift test
swift run dualsense-bridge
```

Hardware smoke tests are documented as the controller integration lands. Do
not paste real session output or credentials into issues, fixtures, or logs.

## License

MIT. See [LICENSE](LICENSE).

