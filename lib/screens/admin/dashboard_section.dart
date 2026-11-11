import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class _Dash {
  _Dash(this.report, this.pending, this.buses);
  final UsageReport report;
  final int pending;
  final int buses;
}

class DashboardSection extends StatelessWidget {
  const DashboardSection({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    return AsyncView<_Dash>(
      load: () async => _Dash(
        await repo.usageReport(),
        (await repo.applications(status: AppStatus.underReview)).length,
        (await repo.buses()).where((b) => b.status == 'ACTIVE').length,
      ),
      builder: (c, d, reload) {
        final maxV = d.report.byRoute.values.fold<int>(1, (a, b) => b > a ? b : a);
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.7,
              children: [
                _Stat('Pending applications', '${d.pending}', Icons.hourglass_top, warnColor),
                _Stat('Active buses', '${d.buses}', Icons.directions_bus, wsuBlue),
                _Stat('Boardings accepted', '${d.report.accepted}', Icons.check_circle, okColor),
                _Stat('Scans rejected', '${d.report.rejected}', Icons.cancel, badColor),
              ],
            ),
            const SectionTitle('Boardings by route'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  for (final e in d.report.byRoute.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        SizedBox(width: 100, child: Text(e.key)),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(value: e.value / maxV, minHeight: 12),
                          ),
                        ),
                        SizedBox(width: 36, child: Text('${e.value}', textAlign: TextAlign.right)),
                      ]),
                    ),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon, this.color);
  final String label, value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(children: [Icon(icon, color: color, size: 18), const SizedBox(width: 6), Expanded(child: Text(label, style: const TextStyle(fontSize: 12)))]),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color)),
          ]),
        ),
      );
}

/// Read-only list of all scans (reports.view).
class ScanLogSection extends StatelessWidget {
  const ScanLogSection({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    return AsyncView<List<ScanLog>>(
      load: repo.scanLogs,
      builder: (c, logs, reload) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (logs.isEmpty) const EmptyState(Icons.qr_code_scanner, 'No scans recorded yet.'),
          for (final l in logs)
            Card(
              child: ListTile(
                leading: Icon(l.status == 'ACCEPTED' ? Icons.check_circle : Icons.cancel, color: statusColor(l.status)),
                title: Text(l.studentName),
                subtitle: Text('Trip ${l.tripId} • Bus ${l.busId}\n${fmtDateTime(l.scanTime)}${l.reason == null ? '' : ' • ${l.reason}'}'),
                isThreeLine: true,
                trailing: StatusChip(l.status),
              ),
            ),
        ],
      ),
    );
  }
}
