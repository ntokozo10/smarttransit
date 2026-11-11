import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class _Data {
  _Data(this.alerts, this.routes);
  final List<ServiceAlert> alerts;
  final List<TransportRoute> routes;
}

class AlertsAdminSection extends StatefulWidget {
  const AlertsAdminSection({super.key});
  @override
  State<AlertsAdminSection> createState() => _AlertsAdminSectionState();
}

class _AlertsAdminSectionState extends State<AlertsAdminSection> {
  int _rev = 0;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    return AsyncView<_Data>(
      key: ValueKey(_rev),
      load: () async => _Data(await repo.alerts(), await repo.routes()),
      builder: (c, d, reload) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _create(c, d), icon: const Icon(Icons.add), label: const Text('Alert')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (d.alerts.isEmpty) const EmptyState(Icons.campaign_outlined, 'No active alerts.'),
          for (final a in d.alerts)
            Card(
              child: ListTile(
                leading: Icon(a.severity == 'INFO' ? Icons.info_outline : Icons.warning_amber_rounded, color: statusColor(a.severity)),
                title: Text(a.title),
                subtitle: Text(
                    '${a.message}\n${a.routeId == null ? 'All routes' : d.routes.firstWhere((r) => r.id == a.routeId).name} • ${fmtDateTime(a.createdAt)}'),
                isThreeLine: true,
                trailing: IconButton(
                  tooltip: 'Close alert',
                  icon: const Icon(Icons.done_all),
                  onPressed: () async {
                    final ok = await guarded(c, () => repo.deactivateAlert(a.id), ok: 'Alert closed.');
                    if (ok) setState(() => _rev++);
                  },
                ),
              ),
            ),
          const SizedBox(height: 70),
        ]),
      ),
    );
  }

  Future<void> _create(BuildContext c, _Data d) async {
    final repo = context.read<AppState>().repo;
    final title = TextEditingController();
    final msg = TextEditingController();
    String sev = 'INFO';
    int? routeId;
    final ok = await showDialog<bool>(
      context: c,
      builder: (dlg) => StatefulBuilder(
        builder: (dlg, set) => AlertDialog(
          title: const Text('New service alert'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 12),
              TextField(controller: msg, maxLines: 3, decoration: const InputDecoration(labelText: 'Message')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: sev,
                decoration: const InputDecoration(labelText: 'Severity'),
                items: const [
                  DropdownMenuItem(value: 'INFO', child: Text('Info')),
                  DropdownMenuItem(value: 'WARNING', child: Text('Warning')),
                  DropdownMenuItem(value: 'CRITICAL', child: Text('Critical')),
                ],
                onChanged: (v) => set(() => sev = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: routeId,
                decoration: const InputDecoration(labelText: 'Affects'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('All routes')),
                  for (final r in d.routes) DropdownMenuItem<int?>(value: r.id, child: Text(r.name)),
                ],
                onChanged: (v) => set(() => routeId = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlg, false), child: const Text('Cancel')),
            FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
                onPressed: () => Navigator.pop(dlg, true),
                child: const Text('Publish')),
          ],
        ),
      ),
    );
    final t = title.text.trim(), m = msg.text.trim();
    title.dispose();
    msg.dispose();
    if (ok != true || !c.mounted) return;
    if (t.isEmpty || m.isEmpty) return snack(c, 'Title and message are required', error: true);
    final done = await guarded(c, () => repo.createAlert(title: t, message: m, severity: sev, routeId: routeId), ok: 'Alert published.');
    if (done) setState(() => _rev++);
  }
}
