import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';

/// Boarding verification: camera QR scan or manual token entry.
/// The server makes the decision; offline scans are queued for sync.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, required this.trip, required this.routeName, required this.busId});
  final Trip trip;
  final String routeName;
  final int busId;
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _Outcome {
  _Outcome(this.color, this.icon, this.title, this.subtitle);
  final Color color;
  final IconData icon;
  final String title, subtitle;
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  final _manual = TextEditingController();
  _Outcome? _outcome;
  bool _busy = false;
  int _ok = 0, _bad = 0, _queued = 0;
  Timer? _clear;
  String? _lastRaw;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _clear?.cancel();
    _controller.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _handle(String raw) async {
    final now = DateTime.now();
    // Ignore the same code re-read within 3 seconds.
    if (_busy || (raw == _lastRaw && now.difference(_lastAt).inSeconds < 3)) return;
    _lastRaw = raw;
    _lastAt = now;
    setState(() => _busy = true);
    final state = context.read<AppState>();
    final req = ScanRequest(
      token: raw.trim(),
      tripId: widget.trip.id,
      busId: widget.busId,
      scannedAt: now,
      clientId: '${now.microsecondsSinceEpoch}-${raw.hashCode}',
    );
    _Outcome out;
    try {
      final r = await state.scan(req);
      if (r == null) {
        _queued++;
        out = _Outcome(warnColor, Icons.cloud_off, 'Saved offline', 'Will sync when connected');
      } else if (r.accepted) {
        _ok++;
        out = _Outcome(okColor, Icons.check_circle, r.studentName ?? 'Accepted',
            [r.studentNumber, r.message].whereType<String>().join(' • '));
      } else {
        _bad++;
        out = _Outcome(badColor, Icons.cancel, r.status == 'DUPLICATE' ? 'Already scanned' : 'Rejected', r.message);
      }
    } catch (e) {
      out = _Outcome(badColor, Icons.error_outline, 'Error', e.toString());
    }
    if (!mounted) return;
    setState(() {
      _outcome = out;
      _busy = false;
    });
    _clear?.cancel();
    _clear = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _outcome = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.trip;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.routeName} • ${t.departure}'),
        actions: [
          IconButton(icon: const Icon(Icons.flash_on), onPressed: _controller.toggleTorch),
          IconButton(icon: const Icon(Icons.cameraswitch), onPressed: _controller.switchCamera),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            MobileScanner(
              controller: _controller,
              onDetect: (cap) {
                final raw = cap.barcodes.isEmpty ? null : cap.barcodes.first.rawValue;
                if (raw != null) _handle(raw);
              },
              errorBuilder: (c, e, w) => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Camera unavailable. Enter the pass code manually below.',
                      textAlign: TextAlign.center),
                ),
              ),
            ),
            Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            if (_outcome != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Material(
                  color: _outcome!.color,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Icon(_outcome!.icon, color: Colors.white, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_outcome!.title,
                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                          if (_outcome!.subtitle.isNotEmpty)
                            Text(_outcome!.subtitle, style: const TextStyle(color: Colors.white)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            if (_busy) const Center(child: CircularProgressIndicator()),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _Counter('Accepted', _ok, okColor),
                _Counter('Rejected', _bad, badColor),
                _Counter('Queued', _queued, warnColor),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _manual,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                        isDense: true, labelText: 'Manual pass code', prefixIcon: Icon(Icons.keyboard)),
                    onSubmitted: (_) => _submitManual(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(80, 48)),
                  onPressed: _submitManual,
                  child: const Text('Check'),
                ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  void _submitManual() {
    final v = _manual.text.trim();
    if (v.isEmpty) return;
    _lastRaw = null; // manual entries are never debounced
    _handle(v);
    _manual.clear();
  }
}

class _Counter extends StatelessWidget {
  const _Counter(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text('$value', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);
}
