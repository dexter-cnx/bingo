# Bingo QR

Flutter Bingo game using ggwave audio as the primary transport and QR as a fallback.

## Transport

- Audio number packet: `[gid, number, seq]`
- Winner packet: `[gid, 0xFF, playerId]`
- QR join: `BINGO:JOIN:<gid>`
- QR number fallback: `BINGO:NUM:<gid>:<num>:<seq>`
- Audible Fast and Ultrasonic Fast modes
- Ultrasonic frequency slider 8–19 kHz, default 12 kHz
- QR fallback for players outside reliable acoustic range

## ggwave dependency

This app consumes the packages maintained in https://github.com/dexter-cnx/ggwave rather than embedding a second copy of the Rust transport.

Until `ggwave_dart` and `ggwave_flutter` are published to pub.dev, `pubspec.yaml` uses Git dependencies with package paths. After publication these can be replaced with normal `^1.2.0` dependencies.

## Run

```bash
flutter pub get
flutter run
```

If native platform boilerplate is missing after cloning, run:

```bash
flutter create --platforms=android,ios .
flutter pub get
flutter run
```

Microphone and camera permissions are required for ggwave receive and QR scanning.
