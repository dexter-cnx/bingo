import 'dart:typed_data';

enum BingoEventType { join, number, winner, end }

enum BingoTransportSource { audio, qr }

class BingoEvent {
  const BingoEvent._({
    required this.type,
    required this.gameId,
    this.number,
    this.sequence,
    this.playerId,
  });

  const BingoEvent.join(int gameId)
      : this._(type: BingoEventType.join, gameId: gameId);

  const BingoEvent.number(int gameId, int number, int sequence)
      : this._(
          type: BingoEventType.number,
          gameId: gameId,
          number: number,
          sequence: sequence,
        );

  const BingoEvent.winner(int gameId, int playerId)
      : this._(
          type: BingoEventType.winner,
          gameId: gameId,
          playerId: playerId,
        );

  const BingoEvent.end(int gameId, int sequence)
      : this._(
          type: BingoEventType.end,
          gameId: gameId,
          sequence: sequence,
        );

  final BingoEventType type;
  final int gameId;
  final int? number;
  final int? sequence;
  final int? playerId;

  String get identityKey => switch (type) {
        BingoEventType.join => 'join:$gameId',
        BingoEventType.number => 'number:$gameId:$number:$sequence',
        BingoEventType.winner => 'winner:$gameId:$playerId',
        BingoEventType.end => 'end:$gameId:$sequence',
      };
}

/// Bingo-owned wire protocol.
///
/// Audio keeps the original compact 3-byte format for backward compatibility:
/// * number: `[gameId, number, sequence]`
/// * winner: `[gameId, 0xFF, playerId]`
/// * end: `[gameId, 0x00, sequence]`
///
/// QR is an application fallback and is decoded into the same [BingoEvent]
/// model before validation.
class BingoProtocolCodec {
  const BingoProtocolCodec._();

  static Uint8List encodeNumber(int gameId, int number, int sequence) =>
      Uint8List.fromList(<int>[
        gameId & 0xFF,
        number & 0xFF,
        sequence & 0xFF,
      ]);

  static Uint8List encodeWinner(int gameId, int playerId) =>
      Uint8List.fromList(<int>[gameId & 0xFF, 0xFF, playerId & 0xFF]);

  static Uint8List encodeEnd(int gameId, int sequence) =>
      Uint8List.fromList(<int>[gameId & 0xFF, 0x00, sequence & 0xFF]);

  static BingoEvent? decodeAudio(Uint8List payload) {
    if (payload.length != 3) return null;
    final gameId = payload[0];
    final value = payload[1];
    final tail = payload[2];
    if (value == 0xFF) return BingoEvent.winner(gameId, tail);
    if (value == 0x00) return BingoEvent.end(gameId, tail);
    if (value < 1 || value > 75) return null;
    return BingoEvent.number(gameId, value, tail);
  }

  static String encodeQrJoin(int gameId) => 'BINGO:JOIN:${gameId & 0xFF}';

  static String encodeQrNumber(int gameId, int number, int sequence) =>
      'BINGO:NUM:${gameId & 0xFF}:$number:${sequence & 0xFF}';

  static BingoEvent? decodeQr(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length == 3 &&
        parts[0] == 'BINGO' &&
        parts[1] == 'JOIN') {
      final gameId = int.tryParse(parts[2]);
      if (!_isByte(gameId)) return null;
      return BingoEvent.join(gameId!);
    }
    if (parts.length == 5 &&
        parts[0] == 'BINGO' &&
        parts[1] == 'NUM') {
      final gameId = int.tryParse(parts[2]);
      final number = int.tryParse(parts[3]);
      final sequence = int.tryParse(parts[4]);
      if (!_isByte(gameId) ||
          number == null ||
          number < 1 ||
          number > 75 ||
          !_isByte(sequence)) {
        return null;
      }
      return BingoEvent.number(gameId!, number, sequence!);
    }
    return null;
  }

  static bool _isByte(int? value) => value != null && value >= 0 && value <= 255;
}

enum BingoIngressDecision {
  accepted,
  duplicate,
  stale,
  wrongGame,
  malformed,
}

class BingoIngressResult {
  const BingoIngressResult(this.decision, {this.event, this.source});

  final BingoIngressDecision decision;
  final BingoEvent? event;
  final BingoTransportSource? source;

  bool get accepted => decision == BingoIngressDecision.accepted;
}

/// App-level game/session validation shared by audio and QR fallback.
class BingoEventGate {
  BingoEventGate(this.gameId);

  int gameId;
  int? _latestSequence;
  final Set<String> _seenEvents = <String>{};
  final Set<int> _seenWinners = <int>{};

  void reset(int newGameId) {
    gameId = newGameId;
    _latestSequence = null;
    _seenEvents.clear();
    _seenWinners.clear();
  }

  BingoIngressResult accept(
    BingoEvent? event, {
    required BingoTransportSource source,
  }) {
    if (event == null) {
      return BingoIngressResult(BingoIngressDecision.malformed, source: source);
    }
    if (event.gameId != gameId) {
      return BingoIngressResult(
        BingoIngressDecision.wrongGame,
        event: event,
        source: source,
      );
    }
    if (event.type == BingoEventType.join) {
      return BingoIngressResult(
        BingoIngressDecision.accepted,
        event: event,
        source: source,
      );
    }
    if (event.type == BingoEventType.winner) {
      final playerId = event.playerId!;
      if (!_seenWinners.add(playerId)) {
        return BingoIngressResult(
          BingoIngressDecision.duplicate,
          event: event,
          source: source,
        );
      }
      return BingoIngressResult(
        BingoIngressDecision.accepted,
        event: event,
        source: source,
      );
    }

    final key = event.identityKey;
    if (!_seenEvents.add(key)) {
      return BingoIngressResult(
        BingoIngressDecision.duplicate,
        event: event,
        source: source,
      );
    }

    final sequence = event.sequence!;
    final latest = _latestSequence;
    if (latest != null && !_isNewer(sequence, latest)) {
      return BingoIngressResult(
        BingoIngressDecision.stale,
        event: event,
        source: source,
      );
    }
    _latestSequence = sequence;
    if (_seenEvents.length > 512) {
      _seenEvents
        ..clear()
        ..add(key);
    }
    return BingoIngressResult(
      BingoIngressDecision.accepted,
      event: event,
      source: source,
    );
  }

  static bool _isNewer(int incoming, int latest) {
    if (incoming == latest) return false;
    final delta = (incoming - latest) & 0xFF;
    return delta > 0 && delta < 128;
  }
}
