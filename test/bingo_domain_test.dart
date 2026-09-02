import 'dart:typed_data';

import 'package:bingo_qr/domain/bingo_board.dart';
import 'package:bingo_qr/domain/bingo_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BingoBoard', () {
    test('generation is deterministic', () {
      final a = BingoBoard.generate(gameId: 7, playerId: 3);
      final b = BingoBoard.generate(gameId: 7, playerId: 3);
      expect(a.cells, b.cells);
    });

    test('FREE center is marked', () {
      final board = BingoBoard.generate(gameId: 7, playerId: 1);
      expect(board.cells[2][2], isNull);
      expect(board.marked[2][2], isTrue);
    });

    test('all numbers are 1..75 and unique', () {
      final board = BingoBoard.generate(gameId: 12, playerId: 9);
      final values = board.cells.expand((row) => row).whereType<int>().toList();
      expect(values, hasLength(24));
      expect(values.every((value) => value >= 1 && value <= 75), isTrue);
      expect(values.toSet(), hasLength(24));
    });

    test('detects row, column and both diagonal wins', () {
      final row = BingoBoard.generate(gameId: 1, playerId: 1);
      for (final value in row.cells[0].whereType<int>()) {
        row.mark(value);
      }
      expect(row.hasBingo, isTrue);

      final column = BingoBoard.generate(gameId: 2, playerId: 1);
      for (var r = 0; r < 5; r++) {
        final value = column.cells[r][0];
        if (value != null) column.mark(value);
      }
      expect(column.hasBingo, isTrue);

      final diagonal = BingoBoard.generate(gameId: 3, playerId: 1);
      for (var i = 0; i < 5; i++) {
        final value = diagonal.cells[i][i];
        if (value != null) diagonal.mark(value);
      }
      expect(diagonal.hasBingo, isTrue);

      final anti = BingoBoard.generate(gameId: 4, playerId: 1);
      for (var i = 0; i < 5; i++) {
        final value = anti.cells[i][4 - i];
        if (value != null) anti.mark(value);
      }
      expect(anti.hasBingo, isTrue);
    });
  });

  group('BingoProtocolCodec', () {
    test('audio number encode/decode', () {
      final payload = BingoProtocolCodec.encodeNumber(7, 42, 9);
      final event = BingoProtocolCodec.decodeAudio(payload);
      expect(event?.type, BingoEventType.number);
      expect(event?.gameId, 7);
      expect(event?.number, 42);
      expect(event?.sequence, 9);
    });

    test('winner event preserves legacy packet format', () {
      final payload = BingoProtocolCodec.encodeWinner(7, 3);
      expect(payload, Uint8List.fromList(<int>[7, 0xFF, 3]));
      final event = BingoProtocolCodec.decodeAudio(payload);
      expect(event?.type, BingoEventType.winner);
      expect(event?.playerId, 3);
    });

    test('QR join and number parse', () {
      final join = BingoProtocolCodec.decodeQr('BINGO:JOIN:7');
      expect(join?.type, BingoEventType.join);
      expect(join?.gameId, 7);

      final number = BingoProtocolCodec.decodeQr('BINGO:NUM:7:42:9');
      expect(number?.type, BingoEventType.number);
      expect(number?.number, 42);
      expect(number?.sequence, 9);
    });

    test('malformed packets are rejected', () {
      expect(BingoProtocolCodec.decodeAudio(Uint8List.fromList(<int>[1, 2])), isNull);
      expect(BingoProtocolCodec.decodeQr('BINGO:NUM:7:99:1'), isNull);
      expect(BingoProtocolCodec.decodeQr('BINGO:JOIN:999'), isNull);
      expect(BingoProtocolCodec.decodeQr('garbage'), isNull);
    });
  });

  group('BingoEventGate', () {
    test('rejects duplicate and stale number events', () {
      final gate = BingoEventGate(7);
      final first = BingoEvent.number(7, 10, 10);
      expect(
        gate.accept(first, source: BingoTransportSource.audio).decision,
        BingoIngressDecision.accepted,
      );
      expect(
        gate.accept(first, source: BingoTransportSource.qr).decision,
        BingoIngressDecision.duplicate,
      );
      expect(
        gate
            .accept(
              const BingoEvent.number(7, 11, 9),
              source: BingoTransportSource.audio,
            )
            .decision,
        BingoIngressDecision.stale,
      );
    });

    test('rejects wrong game ID', () {
      final gate = BingoEventGate(7);
      expect(
        gate
            .accept(
              const BingoEvent.number(8, 42, 1),
              source: BingoTransportSource.audio,
            )
            .decision,
        BingoIngressDecision.wrongGame,
      );
    });

    test('audio and QR same event deduplicate', () {
      final gate = BingoEventGate(7);
      final audio = BingoProtocolCodec.decodeAudio(
        BingoProtocolCodec.encodeNumber(7, 42, 9),
      );
      final qr = BingoProtocolCodec.decodeQr('BINGO:NUM:7:42:9');
      expect(
        gate.accept(audio, source: BingoTransportSource.audio).accepted,
        isTrue,
      );
      expect(
        gate.accept(qr, source: BingoTransportSource.qr).decision,
        BingoIngressDecision.duplicate,
      );
    });

    test('winner is accepted once per player', () {
      final gate = BingoEventGate(7);
      const winner = BingoEvent.winner(7, 3);
      expect(
        gate.accept(winner, source: BingoTransportSource.audio).accepted,
        isTrue,
      );
      expect(
        gate.accept(winner, source: BingoTransportSource.audio).decision,
        BingoIngressDecision.duplicate,
      );
    });

    test('sequence wrap 255 -> 1 is accepted', () {
      final gate = BingoEventGate(7);
      expect(
        gate
            .accept(
              const BingoEvent.number(7, 1, 255),
              source: BingoTransportSource.audio,
            )
            .accepted,
        isTrue,
      );
      expect(
        gate
            .accept(
              const BingoEvent.number(7, 2, 1),
              source: BingoTransportSource.audio,
            )
            .accepted,
        isTrue,
      );
    });
  });
}
