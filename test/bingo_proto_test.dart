import 'package:bingo_qr/services/ggwave_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('number packet keeps gid, number, seq', () {
    expect(BingoProto.makeNumber(7, 42, 258), [7, 42, 2]);
  });

  test('QR join parses', () {
    final msg = BingoProto.parseQr('BINGO:JOIN:7');
    expect(msg?.type, QrMessageType.join);
    expect(msg?.gid, 7);
  });

  test('QR number parses', () {
    final msg = BingoProto.parseQr('BINGO:NUM:7:42:9');
    expect(msg?.type, QrMessageType.number);
    expect(msg?.gid, 7);
    expect(msg?.number, 42);
    expect(msg?.seq, 9);
  });
}
