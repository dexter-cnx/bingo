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

This app consumes the universal packages maintained in https://github.com/dexter-cnx/ggwave rather than embedding a second copy of the Rust transport.

The Flutter package is named `ggwave_rs_flutter` because the pub.dev name `ggwave_flutter` is already owned by another project. Until `ggwave_dart` and `ggwave_rs_flutter` are published, `pubspec.yaml` consumes them from the ggwave monorepo via Git paths. After publication these can be replaced with normal `^1.2.0` dependencies.

## Run

```bash
flutter pub get
flutter run
```

Microphone and camera permissions are required for ggwave receive and QR scanning.
