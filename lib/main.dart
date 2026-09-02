import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'pages/caller_page.dart';
import 'pages/player_page.dart';
import 'services/app_permissions.dart';

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
  bool _openingRole = false;

  @override
  void dispose() {
    gid.dispose();
    pid.dispose();
    super.dispose();
  }

  Future<bool> _ensureMicrophone() async {
    final result = await AppPermissions.requestMicrophone();
    if (!mounted || result == AppPermissionResult.granted) {
      return result == AppPermissionResult.granted;
    }

    final permanentlyDenied = result == AppPermissionResult.permanentlyDenied;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ต้องใช้ Microphone'),
        content: Text(
          permanentlyDenied
              ? 'Bingo ใช้ microphone สำหรับรับ acoustic packet กรุณาเปิดสิทธิ์ใน Settings แล้วลองอีกครั้ง'
              : 'Bingo ใช้ microphone สำหรับรับ acoustic packet คุณยังสามารถกลับมาอนุญาตแล้วลองอีกครั้งได้',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
          if (permanentlyDenied)
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
    return false;
  }

  Future<void> _openRole(Widget page) async {
    if (_openingRole) return;
    setState(() => _openingRole = true);
    try {
      if (!await _ensureMicrophone() || !mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    } finally {
      if (mounted) setState(() => _openingRole = false);
    }
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
              'แอปจะขอ microphone ตอนเริ่ม Caller/Player acoustic flow และ camera เมื่อเปิด QR scanner',
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
              onPressed: _openingRole
                  ? null
                  : () => _openRole(CallerPage(gameId: gameId)),
              icon: const Icon(Icons.campaign),
              label: const Text('Caller (มี QR JOIN + QR เลข)'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _openingRole
                  ? null
                  : () => _openRole(
                        PlayerPage(gameId: gameId, playerId: playerId),
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
