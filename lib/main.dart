import 'package:flutter/material.dart';

import 'pages/caller_page.dart';
import 'pages/player_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bingo QR',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
      home: const RoleSelect(),
    );
  }
}

class RoleSelect extends StatefulWidget {
  const RoleSelect({super.key});

  @override
  State<RoleSelect> createState() => _RoleSelectState();
}

class _RoleSelectState extends State<RoleSelect> {
  final gid = TextEditingController(text: '7');
  final pid = TextEditingController(text: '1');

  @override
  void dispose() {
    gid.dispose();
    pid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gameId = int.tryParse(gid.text) ?? 7;
    final playerId = int.tryParse(pid.text) ?? 1;
    return Scaffold(
      appBar: AppBar(title: const Text('Bingo + Audio + QR Fallback')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('1 App • 2 Roles', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            const Text(
              'เสียงเป็นช่องทางหลัก; QR JOIN และ QR เลขเป็น fallback สำหรับคนที่อยู่ไกลหรืออุปกรณ์รับ ultrasonic ไม่ดี',
            ),
            const SizedBox(height: 8),
            const Text(
              'แอปจะขอสิทธิ์ microphone เมื่อเริ่ม acoustic flow และขอ camera เฉพาะตอนเปิด QR scanner',
            ),
            const SizedBox(height: 24),
            TextField(
              controller: gid,
              decoration: const InputDecoration(
                labelText: 'Game ID (0-255 เหมาะกับ audio packet)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pid,
              decoration: const InputDecoration(
                labelText: 'Player ID (0-255)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CallerPage(gameId: gameId)),
              ),
              icon: const Icon(Icons.campaign),
              label: const Text('Caller (มี QR JOIN + QR เลข)'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlayerPage(gameId: gameId, playerId: playerId),
                ),
              ),
              icon: const Icon(Icons.headphones),
              label: const Text('Player (สแกน QR ถ้าไม่ได้ยิน)'),
            ),
          ],
        ),
      ),
    );
  }
}
