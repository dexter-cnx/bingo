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

/// Thin application transport adapter around the universal ggwave package.
///
/// Bingo sequence/order/dedup semantics intentionally do not live here.
class GgwaveService {
  GgwaveService._();

  static final GgWaveFlutterTransport _transport = GgWaveFlutterTransport();
  static final StreamController<Uint8List> _messages =
      StreamController<Uint8List>.broadcast();
  static StreamSubscription<Uint8List>? _nativeSub;
  static bool _initialized = false;

  static Stream<Uint8List> get onMessage => _messages.stream;

  static Future<void> init() async {
    if (_initialized) return;
    await _transport.initialize();
    _nativeSub = _transport.messages.listen(
      _messages.add,
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
    if (!_messages.isClosed) await _messages.close();
  }
}
