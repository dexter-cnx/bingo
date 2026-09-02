import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/ggwave_service.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.gameId, required this.playerId});

  final int gameId;
  final int playerId;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late List<List<int?>> board;
  late List<List<bool>> marked;
  final Set<int> seenSeq = <int>{};
  StreamSubscription<Uint8List>? _sub;

  String log = 'กำลังเตรียมรับเสียง…';
  bool won = false;
  int seq = 0;
  Protocol proto = Protocol.ultrasonicFast;
  double freq = 12000;
  late int curGid;
  bool scanning = false;
  bool _scannerLocked = false;

  @override
  void initState() {
    super.initState();
    curGid = widget.gameId;
    _gen();
    _start();
  }

  void _gen() {
    final random = Random(curGid * 1000 + widget.playerId);
    final nums = List<int>.generate(75, (i) => i + 1)..shuffle(random);
    final picked = nums.take(24).toList();
    var cursor = 0;
    board = List.generate(5, (r) => List.generate(5, (c) {
      if (r == 2 && c == 2) return null;
      return picked[cursor++];
    }));
    marked = List.generate(5, (_) => List<bool>.filled(5, false));
    marked[2][2] = true;
    won = false;
    seenSeq.clear();
  }

  Future<void> _start() async {
    try {
      await GgwaveService.init();
      if (proto.isUltrasonic) await GgwaveService.setUltrasonicFreq(freq);
      await GgwaveService.startListening(proto);
      _sub = GgwaveService.onMessage.listen((payload) {
        if (payload.length < 3 || payload[0] != (curGid & 0xFF)) return;
        _handle(payload[1], payload[2]);
      });
      if (mounted) setState(() => log = 'Listening • ${proto.label}');
    } catch (e) {
      if (mounted) setState(() => log = 'Native bridge: $e');
    }
  }

  void _handle(int num, int incomingSeq) {
    if (incomingSeq != 0 && !seenSeq.add(incomingSeq)) return;
    if (seenSeq.length > 220) seenSeq.clear();
    seq = incomingSeq;
    if (num == 0) {
      setState(() => log = 'เกมจบแล้ว');
      return;
    }
    if (num == 0xFF) return;
    if (num >= 1 && num <= 75) _mark(num);
  }

  void _mark(int num) {
    var changed = false;
    for (var r = 0; r < 5; r++) {
      for (var c = 0; c < 5; c++) {
        if (board[r][c] == num && !marked[r][c]) {
          marked[r][c] = true;
          changed = true;
        }
      }
    }
    if (!changed) {
      setState(() => log = 'ได้เลข $num • ไม่มีบนการ์ด');
      return;
    }
    final hasWon = _win();
    setState(() {
      won = won || hasWon;
      log = hasWon ? 'BINGO! ได้เลข $num' : 'มาร์กเลข $num • seq $seq';
    });
  }

  bool _win() {
    for (var r = 0; r < 5; r++) {
      if (marked[r].every((v) => v)) return true;
    }
    for (var c = 0; c < 5; c++) {
      if (List.generate(5, (r) => marked[r][c]).every((v) => v)) return true;
    }
    if (List.generate(5, (i) => marked[i][i]).every((v) => v)) return true;
    if (List.generate(5, (i) => marked[i][4 - i]).every((v) => v)) return true;
    return false;
  }

  Future<void> sendWin() async {
    try {
      final payload = BingoProto.makeWin(curGid, widget.playerId, seq);
      final wave = await GgwaveService.encode(payload, p: proto, vol: proto.isUltrasonic ? 85 : 60);
      await GgwaveService.play(wave);
      if (mounted) setState(() => log = 'ส่ง BINGO ไป Caller แล้ว');
    } catch (e) {
      if (mounted) setState(() => log = 'ส่ง BINGO ไม่สำเร็จ: $e');
    }
  }

  void _onQr(String raw) {
    final msg = BingoProto.parseQr(raw);
    if (msg == null) {
      setState(() => log = 'QR ไม่ถูกต้อง');
      return;
    }
    if (msg.type == QrMessageType.join) {
      setState(() {
        if (msg.gid != curGid) {
          curGid = msg.gid;
          _gen();
          log = 'เข้าร่วม Game $curGid จาก QR JOIN';
        } else {
          log = 'อยู่ใน Game $curGid แล้ว';
        }
        scanning = false;
      });
      return;
    }
    if (msg.type == QrMessageType.number && msg.gid == curGid) {
      _handle(msg.number!, msg.seq! & 0xFF);
      setState(() => scanning = false);
    } else {
      setState(() => log = 'QR เป็น Game ${msg.gid}, แต่ตอนนี้อยู่ Game $curGid');
    }
  }

  Future<void> _changeProtocol(Protocol? value) async {
    if (value == null || value == proto) return;
    setState(() => proto = value);
    try {
      await GgwaveService.stopListening();
      if (proto.isUltrasonic) await GgwaveService.setUltrasonicFreq(freq);
      await GgwaveService.startListening(proto);
      if (mounted) setState(() => log = 'Listening • ${proto.label}');
    } catch (e) {
      if (mounted) setState(() => log = 'เปลี่ยน protocol ไม่สำเร็จ: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    GgwaveService.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Player ${widget.playerId} • Game $curGid'),
        actions: [IconButton(tooltip: 'Scan QR fallback', onPressed: () => setState(() => scanning = !scanning), icon: const Icon(Icons.qr_code_scanner))],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                DropdownButtonFormField<Protocol>(
                  value: proto,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Protocol', border: OutlineInputBorder()),
                  items: Protocol.values.map((p) => DropdownMenuItem(value: p, child: Text(p.label))).toList(),
                  onChanged: _changeProtocol,
                ),
                if (proto.isUltrasonic) ...[
                  const SizedBox(height: 8),
                  Text('${freq.toStringAsFixed(0)} Hz'),
                  Slider(min: 8000, max: 19000, divisions: 110, value: freq, onChanged: (v) => setState(() => freq = v), onChangeEnd: (v) => GgwaveService.setUltrasonicFreq(v)),
                ],
                Align(alignment: Alignment.centerLeft, child: Text(log)),
                const SizedBox(height: 8),
                Expanded(
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, mainAxisSpacing: 5, crossAxisSpacing: 5),
                    itemCount: 25,
                    itemBuilder: (context, index) {
                      final r = index ~/ 5;
                      final c = index % 5;
                      final value = board[r][c];
                      return Card(
                        color: marked[r][c] ? Colors.green.shade200 : null,
                        child: Center(child: Text(value?.toString() ?? 'FREE', style: const TextStyle(fontWeight: FontWeight.bold))),
                      );
                    },
                  ),
                ),
                if (won) FilledButton.icon(onPressed: sendWin, icon: const Icon(Icons.emoji_events), label: Text('BINGO via ${proto.label}')),
                const SizedBox(height: 8),
                OutlinedButton.icon(onPressed: () => setState(() => scanning = true), icon: const Icon(Icons.qr_code_scanner), label: const Text('สแกน QR Fallback')),
              ],
            ),
          ),
          if (scanning)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black87,
                child: SafeArea(
                  child: Column(
                    children: [
                      AppBar(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        title: const Text('สแกน QR'),
                        automaticallyImplyLeading: false,
                        actions: [IconButton(onPressed: () => setState(() => scanning = false), icon: const Icon(Icons.close))],
                      ),
                      Expanded(
                        child: MobileScanner(
                          onDetect: (capture) {
                            if (_scannerLocked) return;
                            final values = capture.barcodes.map((b) => b.rawValue).whereType<String>();
                            final raw = values.isEmpty ? null : values.first;
                            if (raw == null) return;
                            _scannerLocked = true;
                            _onQr(raw);
                            Future<void>.delayed(const Duration(milliseconds: 700)).then((_) => _scannerLocked = false);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
