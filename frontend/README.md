# frontend — Flutter web spectator UI

The spectator interface for LLM Poker: renders the table, every player's hole cards (face-up by design — this is an AI-vs-AI show match), chip stacks, the action log, and a per-model reasoning panel.

Connects to the Node.js backend over WebSocket (`ws://localhost:3000` by default, overridable with `--dart-define=WS_URL=...`).

```bash
flutter pub get
flutter run -d chrome
```

Tests and static analysis:

```bash
flutter analyze
flutter test
```

See the [root README](../README.md) for the full stack setup.
