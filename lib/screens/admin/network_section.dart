import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/permissions.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class _Data {
  _Data(this.routes, this.residences, this.assignments);
  final List<TransportRoute> routes;
  final List<Residence> residences;
  final List<Assignment> assignments;
}

/// Routes, residences and the academic-year route-residence assignments.
class NetworkSection extends StatefulWidget {
  const NetworkSection({super.key});
  @override
  State<NetworkSection> createState() => _NetworkSectionState();
}

class _NetworkSectionState extends State<NetworkSection> {
  int _rev = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final repo = state.repo;
    final canEdit = state.session!.can(Perm.configManage);
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        const TabBar(tabs: [Tab(text: 'Routes'), Tab(text: 'Residences')]),
        Expanded(
          child: AsyncView<_Data>(
            key: ValueKey(_rev),
            load: () async => _Data(await repo.routes(), await repo.residences(), await repo.assignments()),
            builder: (c, d, reload) => TabBarView(children: [
              _routes(c, d, canEdit),
              _residences(c, d, canEdit),
            ]),
          ),
        ),
      ]),
    );
  }

  void _refresh() => setState(() => _rev++);

  // ---- routes
  Widget _routes(BuildContext c, _Data d, bool canEdit) {
    final repo = context.read<AppState>().repo;
    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _routeDialog(c, null), icon: const Icon(Icons.add), label: const Text('Route'))
          : null,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final r in d.routes)
          Card(
            child: ListTile(
              leading: const Icon(Icons.alt_route),
              title: Text(r.name),
              subtitle: Text(
                  '${r.description ?? ''}\n${d.assignments.where((a) => a.routeId == r.id && a.academicYear == AppConfig.academicYear && a.isActive).length} residences in ${AppConfig.academicYear}'),
              isThreeLine: true,
              trailing: canEdit
                  ? Switch(
                      value: r.isActive,
                      onChanged: (v) async {
                        final ok = await guarded(c, () => repo.saveRoute(id: r.id, name: r.name, description: r.description, isActive: v));
                        if (ok) _refresh();
                      })
                  : StatusChip(r.isActive ? 'ACTIVE' : 'INACTIVE'),
              onTap: canEdit ? () => _routeDialog(c, r) : null,
            ),
          ),
        const SizedBox(height: 70),
      ]),
    );
  }

  Future<void> _routeDialog(BuildContext c, TransportRoute? r) async {
    final repo = context.read<AppState>().repo;
    final name = TextEditingController(text: r?.name);
    final desc = TextEditingController(text: r?.description);
    final ok = await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: Text(r == null ? 'New route' : 'Edit route'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Route name')),
          const SizedBox(height: 12),
          TextField(controller: desc, maxLines: 2, decoration: const InputDecoration(labelText: 'Description')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Save')),
        ],
      ),
    );
    final n = name.text.trim(), ds = desc.text.trim();
    name.dispose();
    desc.dispose();
    if (ok != true || !c.mounted) return;
    if (n.isEmpty) return snack(c, 'Name is required', error: true);
    final done = await guarded(c, () => repo.saveRoute(id: r?.id, name: n, description: ds, isActive: r?.isActive ?? true), ok: 'Route saved.');
    if (done) _refresh();
  }

  // ---- residences
  Widget _residences(BuildContext c, _Data d, bool canEdit) {
    final year = AppConfig.academicYear;
    String routeName(int id) => d.routes.firstWhere((r) => r.id == id).name;
    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _residenceDialog(c, null), icon: const Icon(Icons.add), label: const Text('Residence'))
          : null,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final r in d.residences)
          Builder(builder: (_) {
            final mine = d.assignments.where((a) => a.residenceId == r.id).toList()
              ..sort((a, b) => b.academicYear.compareTo(a.academicYear));
            final current = mine.where((a) => a.academicYear == year && a.isActive).firstOrNull;
            final history = mine.where((a) => a.academicYear != year).toList();
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                    if (!r.isActive) const StatusChip('INACTIVE'),
                    if (canEdit) IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _residenceDialog(c, r)),
                  ]),
                  Row(children: [
                    const Icon(Icons.alt_route, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(current == null ? '$year: no route assigned' : '$year: ${routeName(current.routeId)}',
                          style: TextStyle(fontWeight: FontWeight.w600, color: current == null ? Colors.red : null)),
                    ),
                    if (canEdit)
                      TextButton(onPressed: () => _assignDialog(c, d, r), child: Text(current == null ? 'Assign' : 'Change')),
                  ]),
                  if (history.isNotEmpty)
                    Text('History: ${history.map((a) => '${a.academicYear} ${routeName(a.routeId)}').join(' • ')}',
                        style: TextStyle(fontSize: 12, color: Theme.of(c).colorScheme.outline)),
                ]),
              ),
            );
          }),
        const SizedBox(height: 70),
      ]),
    );
  }

  Future<void> _residenceDialog(BuildContext c, Residence? r) async {
    final repo = context.read<AppState>().repo;
    final name = TextEditingController(text: r?.name);
    final loc = TextEditingController(text: r?.location);
    var active = r?.isActive ?? true;
    final ok = await showDialog<bool>(
      context: c,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(r == null ? 'New residence' : 'Edit residence'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Residence name')),
            const SizedBox(height: 12),
            TextField(controller: loc, decoration: const InputDecoration(labelText: 'Location')),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Active'), value: active, onChanged: (v) => set(() => active = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    final n = name.text.trim(), l = loc.text.trim();
    name.dispose();
    loc.dispose();
    if (ok != true || !c.mounted) return;
    if (n.isEmpty) return snack(c, 'Name is required', error: true);
    final done = await guarded(c, () => repo.saveResidence(id: r?.id, name: n, location: l, isActive: active), ok: 'Residence saved.');
    if (done) _refresh();
  }

  Future<void> _assignDialog(BuildContext c, _Data d, Residence r) async {
    final repo = context.read<AppState>().repo;
    int year = AppConfig.academicYear;
    int? routeId;
    final ok = await showDialog<bool>(
      context: c,
      builder: (dlg) => StatefulBuilder(
        builder: (dlg, set) => AlertDialog(
          title: Text('Assign route — ${r.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              initialValue: year,
              decoration: const InputDecoration(labelText: 'Academic year'),
              items: [for (final y in [year - 1, year, year + 1]) DropdownMenuItem(value: y, child: Text('$y'))],
              onChanged: (v) => set(() => year = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: routeId,
              decoration: const InputDecoration(labelText: 'Route'),
              items: [for (final x in d.routes.where((x) => x.isActive)) DropdownMenuItem(value: x.id, child: Text(x.name))],
              onChanged: (v) => set(() => routeId = v),
            ),
            const SizedBox(height: 8),
            const Text('Earlier years keep their route, so history is preserved. Existing passes are not changed.',
                style: TextStyle(fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlg, false), child: const Text('Cancel')),
            FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
                onPressed: routeId == null ? null : () => Navigator.pop(dlg, true),
                child: const Text('Assign')),
          ],
        ),
      ),
    );
    if (ok != true || routeId == null || !c.mounted) return;
    final done = await guarded(c, () => repo.saveAssignment(residenceId: r.id, routeId: routeId!, year: year), ok: 'Route assigned.');
    if (done) _refresh();
  }
}
