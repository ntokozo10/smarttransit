import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class ApplicationsSection extends StatefulWidget {
  const ApplicationsSection({super.key});
  @override
  State<ApplicationsSection> createState() => _ApplicationsSectionState();
}

class _ApplicationsSectionState extends State<ApplicationsSection> {
  String _filter = AppStatus.underReview;
  int _rev = 0;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    return Column(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          for (final s in AppStatus.all)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(titleCase(s)),
                selected: _filter == s,
                onSelected: (_) => setState(() => _filter = s),
              ),
            ),
        ]),
      ),
      Expanded(
        child: AsyncView<List<Application>>(
          key: ValueKey('$_filter$_rev'),
          load: () => repo.applications(status: _filter),
          builder: (c, apps, reload) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              if (apps.isEmpty) const EmptyState(Icons.inbox_outlined, 'Nothing here.'),
              for (final a in apps)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(a.studentName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                        StatusChip(a.status),
                      ]),
                      const SizedBox(height: 6),
                      KeyValue('Student no.', a.studentNumber),
                      KeyValue('Residence', a.residenceName),
                      KeyValue('Route', a.routeName ?? 'Not assigned for ${DateTime.now().year}'),
                      KeyValue('Applied', fmtDateTime(a.appliedAt)),
                      if (a.reviewedBy != null) KeyValue('Reviewed by', a.reviewedBy!),
                      if (a.rejectionReason != null) KeyValue('Reason', a.rejectionReason!),
                      if (a.status == AppStatus.underReview) ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _reject(c, a),
                              child: const Text('Reject'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                              onPressed: () async {
                                if (!await confirm(c, 'Approve application?',
                                    '${a.studentName} will receive a pass for ${a.routeName ?? 'the assigned route'}.',
                                    ok: 'Approve')) {
                                  return;
                                }
                                if (!c.mounted) return;
                                final ok = await guarded(c, () => repo.approveApplication(a.id),
                                    ok: 'Approved — pass created and student notified.');
                                if (ok) setState(() => _rev++);
                              },
                              child: const Text('Approve'),
                            ),
                          ),
                        ]),
                      ],
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    ]);
  }

  Future<void> _reject(BuildContext c, Application a) async {
    final repo = context.read<AppState>().repo;
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: c,
      builder: (d) => AlertDialog(
        title: Text('Reject ${a.studentName}?'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Reason (shown to the student)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
            onPressed: () => Navigator.pop(d, ctrl.text),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (reason == null || !c.mounted) return;
    final ok = await guarded(c, () => repo.rejectApplication(a.id, reason), ok: 'Application rejected.');
    if (ok) setState(() => _rev++);
  }
}
