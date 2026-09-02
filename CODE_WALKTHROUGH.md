# CODE WALKTHROUGH

## 1. Boundary

Bingo is an application consumer. `lib/services/ggwave_service.dart` is intentionally a thin adapter around `ggwave_rs_flutter`; it does not own Bingo packet parsing, game IDs, sequence rules, duplicate tracking, board state, QR formats, or winner semantics.

```text
Bingo domain/UI
    ↓
GgwaveService
    ↓
ggwave_rs_flutter
    ↓
ggwave_dart / FRB / Rust / ggwave-core
```

A transport/core/package defect belongs in `dexter-cnx/ggwave`. A game/protocol/UI defect belongs here.

## 2. Caller number flow

`CallerPage.callNum()` selects a number not previously called, advances the app-level sequence ID, encodes the existing compact Bingo packet, and hands only bytes to the transport adapter.

```text
Caller generate number
        ↓
BingoProtocolCodec.encodeNumber
        ↓
[gameId, number, seq]
        ↓
GgwaveService.encode/play
        ↓
ggwave_rs_flutter
        ↓
audio
        ↓
Player receive
        ↓
BingoProtocolCodec.decodeAudio
        ↓
BingoEventGate
        ↓
gameId / duplicate / stale / seq validation
        ↓
BingoBoard.mark
```

The Caller then exposes the exact same logical number/sequence as a QR fallback.

## 3. QR fallback flow

QR is not part of ggwave. It is a second Bingo application transport.

```text
same number event
      ↓
BingoProtocolCodec.encodeQrNumber
      ↓
QR image
      ↓
camera scan
      ↓
BingoProtocolCodec.decodeQr
      ↓
BingoEventGate
      ↓
same validation path as acoustic
      ↓
BingoBoard.mark
```

Because both paths converge on `BingoEventGate`, receiving audio first and scanning the QR afterward produces `duplicate` rather than marking twice.

## 4. Protocol compatibility

`lib/domain/bingo_protocol.dart` preserves the existing 3-byte wire format:

```text
number = [gameId, number, sequence]
winner = [gameId, 0xFF, playerId]
end    = [gameId, 0x00, sequence]
```

Winner packets do not gain a new sequence byte because changing packet length/meaning would break existing interoperability. Winner duplication is therefore keyed by `(gameId, playerId)` at the Bingo application layer.

Existing QR strings are preserved:

```text
BINGO:JOIN:<gameId>
BINGO:NUM:<gameId>:<number>:<seq>
```

## 5. Sequence and deduplication

`BingoEventGate` is session-scoped. It rejects:

- wrong game IDs;
- exact duplicate events;
- stale/out-of-order number/end events;
- repeat winner announcements from the same player.

Sequence comparison is modulo 256 and accepts normal rollover such as `255 -> 1`. This logic used to be partially duplicated in the transport service and Player UI; it now lives in the Bingo domain so QR and acoustic behavior stay aligned.

## 6. Board generation

`lib/domain/bingo_board.dart` extracts the original deterministic algorithm from `PlayerPage` without changing it:

```text
seed = gameId * 1000 + playerId
shuffle 1..75
pick first 24
center = FREE
```

This preserves reproducibility/backward compatibility for an existing `(gameId, playerId)` seed. The board object owns marking and row/column/diagonal Bingo detection.

## 7. Winner flow

```text
Player board reaches Bingo
        ↓
BingoProtocolCodec.encodeWinner
        ↓
[gameId, 0xFF, playerId]
        ↓
GgwaveService / ggwave_rs_flutter
        ↓
Caller decodeAudio
        ↓
Caller BingoEventGate
        ↓
first winner event accepted
repeat from same player rejected
```

## 8. Acoustic tuning

The application offers the stable ggwave protocols:

```text
Audible Fast = 1
Ultrasonic Fast = 5
```

Ultrasonic frequency remains adjustable from 8–19 kHz with quick test profiles at 12, 15 and 18 kHz. The UI configures the universal package via `setUltrasonicFrequency`; no ggwave DSP/Rust implementation is copied into Bingo.

## 9. Permissions

Android declares `RECORD_AUDIO` and `CAMERA`. iOS declares microphone and camera usage descriptions. Runtime permission UX remains an application responsibility.

## 10. Tests and local gate

`test/bingo_domain_test.dart` tests the pure application domain without needing acoustic hardware. `Makefile` provides:

```text
make format
make analyze
make test
make check
make run
```

Physical-device acoustic testing is still required before claiming Audible/Ultrasonic roundtrip support as validated.
