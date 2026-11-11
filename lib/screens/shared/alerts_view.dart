import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class _Data {
  _Data(this.alerts, this.notes, this.routes);
  final List<ServiceAlert> alerts;
  final List<AppNotification> notes;
  final List<TransportRoute> routes;
}

/// Service alerts (+ personal notifications for students).
class AlertsView extends StatelessWidget {
  const AlertsView({super.key, this.showNotifications = false});
  final bool showNotifications;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    return AsyncView<_Data>(
      load: () async => _Data(
        await repo.alerts(),
        showNotifications ? await repo.notifications() : [],
        await repo.routes(),
      ),
      builder: (c, d, reload) {
        String routeName(int? id) => id == null
            ? 'All routes'
            : d.routes.firstWhere((r) => r.id == id, orElse: () => TransportRoute(id: id, name: 'Route $id')).name;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (showNotifications && d.notes.isNotEmpty) ...[
              const SectionTitle('Your notifications'),
              for (final n in d.notes)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.mark_email_unread_outlined),
                    title: Text(n.title),
                    subtitle: Text('${n.body}\n${fmtDateTime(n.createdAt)}'),
                    isThreeLine: true,
                  ),
                ),
            ],
            const SectionTitle('Service alerts'),
            if (d.alerts.isEmpty) const EmptyState(Icons.check_circle_outline, 'No active service alerts.'),
            for (final a in d.alerts)
              Card(
                child: ListTile(
                  leading: Icon(
                    a.severity == 'INFO' ? Icons.info_outline : Icons.warning_amber_rounded,
                    color: statusColor(a.severity),
                  ),
                  title: Text(a.title),
                  subtitle: Text('${a.message}\n${routeName(a.routeId)} • ${fmtDateTime(a.createdAt)}'),
                  isThreeLine: true,
                ),
              ),
          ],
        );
      },
    );
  }
}
