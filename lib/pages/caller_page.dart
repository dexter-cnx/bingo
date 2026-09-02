import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/ggwave_service.dart';

class CallerPage extends StatefulWidget {
  const CallerPage({super.key, required this.gameId});

  final int gameId;

  @override
  State<CallerPage> createState() => _CallerPageState();
}

class _CallerPageState extends State<CallerPage> {
  final List<int> called = <int>[];
  final Set<int> winners = <int>{};
  final Random _random = Random();

  StreamSubscription<Uint8List>? _sub;
  int seq = 0;
  String log = 'พร้อมเริ่มเกม';
  Protocol proto = Protocol.ultrasonicFast;
  double freq = 12000;
  int? lastNum;
  bool showQr = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await GgwaveService.init();
      await GgwaveService.setUltrasonicFreq(freq);
      await GgwaveService.startListening(proto);
      _sub = GgwaveService.onMessage.listen((payload) {
        if (payload.length < 3 || payload[0] != (widget.gameId & 0xFF)) return;
        if (payload[1] != 0xFF) return;
        final pid = payload[2];
        if (!mounted) return;
        setState(() {
          winners.add(pid);
          log = 'Player $pid ส่ง BINGO!';
        });
      });
    } catch (e) {
      if (mounted) setState(() => log = 'Native bridge: $e');
    }
  }

  Future<void> callNum() async {
    if (_busy || called.length >= 75) return;
    setState(() => _busy = true);
    try {
      final available = <int>[
        for (var n = 1; n <= 75; n++)
          if (!called.contains(n)) n,
      ];
      final n = available[_random.nextInt(available.length)];
      called.add(n);
      lastNum = n;
      seq = (seq + 1) & 0xFF;
      if (seq == 0) seq = 1;

      if (proto.isUltrasonic) {
        await GgwaveService.setUltrasonicFreq(freq);
      }
      final payload = BingoProto.makeNumber(widget.gameId, n, seq);
      final wave = await GgwaveService.encode(
        payload,
        p: proto,
        vol: proto.isUltrasonic ? 85 : 60,
      );
      await GgwaveService.play(wave);
      if (!mounted) return;
      setState(() {
        showQr = true;
        log = 'ส่งเลข $n • seq $seq • ${proto.label}';
      });
    } catch (e) {
      if (mounted) setState(() => log = 'ส่งไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeProtocol(Protocol? value) async {
    if (value == null || value == proto) return;
    setState(() => proto = value);
    try {
      await GgwaveService.stopListening();
      if (proto.isUltrasonic) await GgwaveService.setUltrasonicFreq(freq);
      await GgwaveService.startListening(proto);
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
      appBar: AppBar(title: Text('Caller • Game ${widget.gameId}')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<Protocol>(
                      value: proto,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Protocol',
                        border: OutlineInputBorder(),
                      ),
                      items: Protocol.values
                          .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
                          .toList(),
                      onChanged: _changeProtocol,
                    ),
                  ),
                  const SizedBox(width: 12),
                  QrImageView(
                    data: BingoProto.makeQrJoin(widget.gameId),
                    size: 80,
                    backgroundColor: Colors.white,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('QR ซ้ายบนคือ QR JOIN'),
              if (proto.isUltrasonic) ...[
                const SizedBox(height: 12),
                Text('Ultrasonic start: ${freq.toStringAsFixed(0)} Hz'),
                Slider(
                  min: 8000,
                  max: 19000,
                  divisions: 110,
                  value: freq,
                  label: '${freq.toStringAsFixed(0)} Hz',
                  onChanged: (v) => setState(() => freq = v),
                  onChangeEnd: (v) => GgwaveService.setUltrasonicFreq(v),
                ),
              ],
              const SizedBox(height: 12),
              Text('เรียกแล้ว ${called.length}/75', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: called.map((n) => Chip(label: Text('$n'))).toList(),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy || called.length >= 75 ? null : callNum,
                icon: const Icon(Icons.campaign),
                label: Text(_busy ? 'กำลังส่ง…' : 'สุ่ม & ส่ง'),
              ),
              if (showQr && lastNum != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: Colors.amber.shade100,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text(
                          'QR Fallback - กรณีอยู่ไกลไม่ได้ยินเสียง',
                          style: TextStyle(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        QrImageView(
                          data: BingoProto.makeQrNumber(widget.gameId, lastNum!, seq),
                          size: 140,
                          backgroundColor: Colors.white,
                        ),
                        Text('เลข $lastNum • seq $seq'),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(log),
              if (winners.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Winners', style: Theme.of(context).textTheme.titleMedium),
                Wrap(
                  spacing: 8,
                  children: winners.map((pid) => Chip(label: Text('Player $pid 🏆'))).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
