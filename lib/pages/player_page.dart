import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/bingo_board.dart';
import '../domain/bingo_protocol.dart';
import '../services/app_permissions.dart';
import '../services/ggwave_service.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.gameId, required this.playerId});

  final int gameId;
  final int playerId;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late BingoBoard board;
  late BingoEventGate gate;
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
    gate = BingoEventGate(curGid);
    _generateBoard();
    _start();
  }

  void _generateBoard() {
    board = BingoBoard.generate(gameId: curGid, playerId: widget.playerId);
    won = false;
  }

  Future<void> _start() async {
    try {
      await GgwaveService.init();
      if (proto.isUltrasonic) await GgwaveService.setUltrasonicFreq(freq);
      await GgwaveService.startListening(proto);
      _sub = GgwaveService.onMessage.listen((payload) {
        final result = gate.accept(
          BingoProtocolCodec.decodeAudio(payload),
          source: BingoTransportSource.audio,
        );
        _applyIngress(result);
      });
      if (mounted) setState(() => log = 'Listening • ${proto.label}');
    } catch (e) {
      if (mounted) setState(() => log = 'Native bridge: $e');
    }
  }

  void _applyIngress(BingoIngressResult result) {
    if (!mounted) return;
    if (!result.accepted) {
      if (result.decision == BingoIngressDecision.wrongGame) {
        setState(() => log = 'ละเว้น packet จาก game อื่น');
      }
      return;
    }
    final event = result.event!;
    switch (event.type) {
      case BingoEventType.number:
        seq = event.sequence!;
        _mark(event.number!);
        break;
      case BingoEventType.end:
        seq = event.sequence!;
        setState(() => log = 'เกมจบแล้ว');
        break;
      case BingoEventType.join:
      case BingoEventType.winner:
        break;
    }
  }

  void _mark(int number) {
    final changed = board.mark(number);
    if (!changed) {
      setState(() => log = 'ได้เลข $number • ไม่มีบนการ์ด');
      return;
    }
    final hasWon = board.hasBingo;
    setState(() {
      won = won || hasWon;
      log = hasWon ? 'BINGO! ได้เลข $number' : 'มาร์กเลข $number • seq $seq';
    });
  }

  Future<void> sendWin() async {
    try {
      final payload = BingoProtocolCodec.encodeWinner(curGid, widget.playerId);
      final wave = await GgwaveService.encode(
        payload,
        p: proto,
        vol: proto.isUltrasonic ? 85 : 60,
      );
      await GgwaveService.play(wave);
      if (mounted) setState(() => log = 'ส่ง BINGO ไป Caller แล้ว');
    } catch (e) {
      if (mounted) setState(() => log = 'ส่ง BINGO ไม่สำเร็จ: $e');
    }
  }

  void _onQr(String raw) {
    final event = BingoProtocolCodec.decodeQr(raw);
    if (event == null) {
      setState(() => log = 'QR ไม่ถูกต้อง');
      return;
    }
    if (event.type == BingoEventType.join) {
      setState(() {
        if (event.gameId != curGid) {
          curGid = event.gameId;
          gate.reset(curGid);
          _generateBoard();
          log = 'เข้าร่วม Game $curGid จาก QR JOIN';
        } else {
          log = 'อยู่ใน Game $curGid แล้ว';
        }
        scanning = false;
      });
      return;
    }

    final result = gate.accept(event, source: BingoTransportSource.qr);
    _applyIngress(result);
    if (mounted) setState(() => scanning = false);
  }

  Future<void> _openScanner() async {
    final result = await AppPermissions.requestCamera();
    if (!mounted) return;
    if (result == AppPermissionResult.granted) {
      setState(() => scanning = true);
      return;
    }

    final permanentlyDenied = result == AppPermissionResult.permanentlyDenied;
    setState(() {
      log = permanentlyDenied
          ? 'Camera ถูกปิดถาวร กรุณาเปิดใน Settings เพื่อใช้ QR fallback'
          : 'ไม่ได้รับสิทธิ์ Camera — acoustic receive ยังใช้งานต่อได้';
    });
    if (!permanentlyDenied) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ต้องใช้ Camera สำหรับ QR'),
        content: const Text(
          'QR เป็น fallback เท่านั้น คุณยังเล่นผ่าน acoustic ได้ หรือเปิด Camera ใน Settings แล้วกลับมาสแกนอีกครั้ง',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            child: const Text('เปิด Settings'),
          ),
        ],
      ),
    );
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
        actions: [
          IconButton(
            tooltip: 'Scan QR fallback',
            onPressed: scanning ? () => setState(() => scanning = false) : _openScanner,
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                DropdownButtonFormField<Protocol>(
                  initialValue: proto,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Protocol',
                    border: OutlineInputBorder(),
                  ),
                  items: Protocol.values
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(p.label),
                        ),
                      )
                      .toList(),
                  onChanged: _changeProtocol,
                ),
                if (proto.isUltrasonic) ...[
                  const SizedBox(height: 8),
                  Text('${freq.toStringAsFixed(0)} Hz'),
                  Slider(
                    min: 8000,
                    max: 19000,
                    divisions: 110,
                    value: freq,
                    onChanged: (value) => setState(() => freq = value),
                    onChangeEnd: GgwaveService.setUltrasonicFreq,
                  ),
                  Wrap(
                    spacing: 8,
                    children: [12000.0, 15000.0, 18000.0]
                        .map(
                          (value) => ActionChip(
                            label: Text('${(value / 1000).toStringAsFixed(0)} kHz'),
                            onPressed: () {
                              setState(() => freq = value);
                              GgwaveService.setUltrasonicFreq(value);
                            },
                          ),
                        )
                        .toList(),
                  ),
                ],
                Align(alignment: Alignment.centerLeft, child: Text(log)),
                const SizedBox(height: 8),
                Expanded(
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      mainAxisSpacing: 5,
                      crossAxisSpacing: 5,
                    ),
                    itemCount: 25,
                    itemBuilder: (context, index) {
                      final row = index ~/ 5;
                      final column = index % 5;
                      final value = board.cells[row][column];
                      return Card(
                        color: board.marked[row][column]
                            ? Colors.green.shade200
                            : null,
                        child: Center(
                          child: Text(
                            value?.toString() ?? 'FREE',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (won)
                  FilledButton.icon(
                    onPressed: sendWin,
                    icon: const Icon(Icons.emoji_events),
                    label: Text('BINGO via ${proto.label}'),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _openScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('สแกน QR Fallback'),
                ),
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
                        actions: [
                          IconButton(
                            onPressed: () => setState(() => scanning = false),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      Expanded(
                        child: MobileScanner(
                          onDetect: (capture) {
                            if (_scannerLocked) return;
                            final values = capture.barcodes
                                .map((barcode) => barcode.rawValue)
                                .whereType<String>();
                            final raw = values.isEmpty ? null : values.first;
                            if (raw == null) return;
                            _scannerLocked = true;
                            _onQr(raw);
                            Future<void>.delayed(
                              const Duration(milliseconds: 700),
                            ).then((_) => _scannerLocked = false);
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
