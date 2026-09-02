import 'dart:async';
import 'dart:typed_data';

import 'package:ggwave_rs_flutter/ggwave_rs_flutter.dart';

enum Protocol {
  audibleFast(1, false, 'Audible Fast', GgWaveProtocol.audibleFast),
  ultrasonicFast(5, true, 'Ultrasonic Fast', GgWaveProtocol.ultrasonicFast);

  const Protocol(this.id, this.isUltrasonic, this.label, this.native);

  final int id;
  final bool isUltrasonic;
  final String label;
  final GgWaveProtocol native;
}

class GgwaveService {
  GgwaveService._();

  static final GgWaveFlutterTransport _transport = GgWaveFlutterTransport();
  static final StreamController<Uint8List> _messages =
      StreamController<Uint8List>.broadcast();
  static final Set<int> _seenSequences = <int>{};
  static StreamSubscription<Uint8List>? _nativeSub;
  static bool _initialized = false;

  static Stream<Uint8List> get onMessage => _messages.stream;

  static Future<void> init() async {
    if (_initialized) return;
    await _transport.initialize();
    _nativeSub = _transport.messages.listen(
      (payload) {
        if (payload.length >= 3) {
          final seq = payload[2];
          if (seq != 0xFF && !_seenSequences.add(seq)) return;
          if (_seenSequences.length > 220) _seenSequences.clear();
        }
        _messages.add(payload);
      },
      onError: _messages.addError,
    );
    _initialized = true;
  }

  static Future<void> setUltrasonicFreq(double frequency) =>
      _transport.setUltrasonicFrequency(frequency);

  static Future<Float32List> encode(
    List<int> data, {
    Protocol p = Protocol.audibleFast,
    int vol = 60,
  }) {
    final effectiveVolume = p.isUltrasonic && vol < 70 ? 85 : vol;
    return _transport.encode(
      Uint8List.fromList(data),
      protocol: p.native,
      volume: effectiveVolume,
    );
  }

  static Future<void> play(Float32List waveform) => _transport.play(waveform);

  static Future<void> startListening(Protocol protocol) =>
      _transport.startListening(protocol: protocol.native);

  static Future<void> stopListening() => _transport.stopListening();

  static Future<void> dispose() async {
    await _nativeSub?.cancel();
    _nativeSub = null;
    await _transport.dispose();
    await _messages.close();
  }
}

class BingoProto {
  const BingoProto._();

  static List<int> makeNumber(int gid, int num, int seq) =>
      <int>[gid & 0xFF, num & 0xFF, seq & 0xFF];

  static List<int> makeWin(int gid, int pid, int seq) =>
      <int>[gid & 0xFF, 0xFF, pid & 0xFF];

  static String makeQrJoin(int gid) => 'BINGO:JOIN:$gid';

  static String makeQrNumber(int gid, int num, int seq) =>
      'BINGO:NUM:$gid:$num:$seq';

  static QrMessage? parseQr(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length == 3 && parts[0] == 'BINGO' && parts[1] == 'JOIN') {
      final gid = int.tryParse(parts[2]);
      return gid == null ? null : QrMessage.join(gid);
    }
    if (parts.length == 5 && parts[0] == 'BINGO' && parts[1] == 'NUM') {
      final gid = int.tryParse(parts[2]);
      final num = int.tryParse(parts[3]);
      final seq = int.tryParse(parts[4]);
      if (gid == null || num == null || seq == null || num < 1 || num > 75) {
        return null;
      }
      return QrMessage.number(gid, num, seq);
    }
    return null;
  }
}

enum QrMessageType { join, number }

class QrMessage {
  const QrMessage._(this.type, this.gid, this.number, this.seq);

  const QrMessage.join(int gid) : this._(QrMessageType.join, gid, null, null);

  const QrMessage.number(int gid, int number, int seq)
      : this._(QrMessageType.number, gid, number, seq);

  final QrMessageType type;
  final int gid;
  final int? number;
  final int? seq;
}
