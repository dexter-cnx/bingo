# Bingo QR

Local/offline Bingo 1–75 for multiple phones. Acoustic transport is provided by the universal `ggwave_rs_flutter` package; QR is a Bingo-owned fallback transport. No backend server is required.

## Architecture

```text
bingo application
   ↓
ggwave_rs_flutter
   ↓
ggwave_dart
   ↓
FRB / Rust
   ↓
ggwave-core
```

Bingo game rules, packet semantics, session validation, ordering/deduplication, QR payloads and winner handling stay in this repository. Rust/ggwave implementation is not duplicated here.

## Toolchain

- Flutter >= 3.47.0
- Dart >= 3.12.0
- ggwave_rs_flutter from `dexter-cnx/ggwave/packages/ggwave_flutter`
- FRB baseline is owned by the ggwave package

Until the packages are published, `pubspec.yaml` uses Git dependencies for `ggwave_rs_flutter` and an override for `ggwave_dart`.

## Game flow

Caller creates a game/session and calls numbers. The number event is encoded by Bingo, passed to `ggwave_rs_flutter`, and sent using Audible Fast or Ultrasonic Fast. Player devices decode the acoustic payload, then pass it through Bingo's shared event gate before marking the board.

If acoustic receive fails, the Caller shows the same event as a QR payload. QR decode enters the same Bingo validation path, so scanning a fallback QR after already receiving the audio packet does not apply the number twice.

## Protocol compatibility

The current compact audio format is intentionally preserved:

```text
number: [gameId, number, sequence]
winner: [gameId, 0xFF, playerId]
end:    [gameId, 0x00, sequence]
```

Current QR fallback remains compatible with:

```text
BINGO:JOIN:<gameId>
BINGO:NUM:<gameId>:<number>:<seq>
```

`BingoEventGate` owns app-level game ID validation, sequence ordering, duplicate rejection, stale-event rejection, winner deduplication, and audio/QR same-event deduplication.

## Board generation

Boards are deterministic from `gameId` + `playerId` and preserve the original app algorithm so an existing game/player seed continues to reproduce the same board. The center cell is always FREE and pre-marked.

## Acoustic profiles

Stable ggwave protocol IDs:

- Audible Fast = 1
- Ultrasonic Fast = 5

Ultrasonic UI supports 8–19 kHz and exposes 12, 15 and 18 kHz quick profiles. Acoustic support is implementation-present only; this repository does not claim physical-device acoustic validation until it is tested on real devices.

## Permissions

Android declares microphone and camera permissions. iOS declares `NSMicrophoneUsageDescription` and `NSCameraUsageDescription`. The app requests runtime permission because receive and QR scan are application UX concerns.

## Local checks

```bash
make format
make analyze
make test
make check
make run
```

`make check` runs formatting, analysis and tests. Use Flutter 3.47+ so the local toolchain matches the ggwave package baseline.

## Test coverage

Domain tests cover deterministic board generation, FREE center, number range/uniqueness, row/column/diagonal Bingo detection, audio packet encoding/decoding, QR parsing, malformed packets, sequence ordering, duplicate/stale events, wrong game IDs, audio+QR same-event deduplication, sequence wrap and winner deduplication.

See `CODE_WALKTHROUGH.md` for the important code paths.
