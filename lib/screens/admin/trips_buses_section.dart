import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/permissions.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class _TripData {
  _TripData(this.routes, this.trips);
  final List<TransportRoute> routes;
  final List<Trip> trips;
}

class TripsSection extends StatefulWidget {
  const TripsSection({super.key});
  @override
  State<TripsSection> createState() => _TripsSectionState();
}

class _TripsSectionState extends State<TripsSection> {
  int _rev = 0;
  int? _routeId;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final repo = state.repo;
    final canEdit = state.session!.can(Perm.tripManage);
    return AsyncView<_TripData>(
      key: ValueKey(_rev),
      load: () async => _TripData(await repo.routes(), await repo.trips()),
      builder: (c, d, reload) {
        _routeId ??= d.routes.isEmpty ? null : d.routes.first.id;
        final trips = d.trips.where((t) => t.routeId == _routeId).toList();
        return Scaffold(
          floatingActionButton: canEdit
              ? FloatingActionButton.extended(
                  onPressed: () => _dialog(c, d, null), icon: const Icon(Icons.add), label: const Text('Trip'))
              : null,
          body: ListView(padding: const EdgeInsets.all(16), children: [
            DropdownButtonFormField<int>(
              initialValue: _routeId,
              decoration: const InputDecoration(labelText: 'Route'),
              items: [for (final r in d.routes) DropdownMenuItem(value: r.id, child: Text(r.name))],
              onChanged: (v) => setState(() => _routeId = v),
            ),
            const SizedBox(height: 8),
            if (trips.isEmpty) const EmptyState(Icons.schedule, 'No trips for this route.'),
            for (final t in trips)
              Card(
                child: ListTile(
                  leading: Icon(t.direction == 'INBOUND' ? Icons.north_east : Icons.south_west),
                  title: Text(t.departure, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                  subtitle: Text('${t.direction == 'INBOUND' ? 'To campus' : 'From campus'} • ${titleCase(t.tripType)}'),
                  trailing: canEdit
                      ? Switch(
                          value: t.isActive,
                          onChanged: (v) async {
                            final ok = await guarded(
                                c,
                                () => repo.saveTrip(
                                    id: t.id,
                                    routeId: t.routeId,
                                    departure: t.departure,
                                    direction: t.direction,
                                    tripType: t.tripType,
                                    isActive: v));
                            if (ok) setState(() => _rev++);
                          })
                      : StatusChip(t.isActive ? 'ACTIVE' : 'INACTIVE'),
                  onTap: canEdit ? () => _dialog(c, d, t) : null,
                ),
              ),
            const SizedBox(height: 70),
          ]),
        );
      },
    );
  }

  Future<void> _dialog(BuildContext c, _TripData d, Trip? t) async {
    final repo = context.read<AppState>().repo;
    int routeId = t?.routeId ?? _routeId ?? d.routes.first.id;
    String dir = t?.direction ?? 'INBOUND';
    String type = t?.tripType ?? 'REGULAR';
    TimeOfDay time = t == null
        ? const TimeOfDay(hour: 7, minute: 0)
        : TimeOfDay(hour: int.parse(t.departure.substring(0, 2)), minute: int.parse(t.departure.substring(3, 5)));
    final ok = await showDialog<bool>(
      context: c,
      builder: (dlg) => StatefulBuilder(
        builder: (dlg, set) => AlertDialog(
          title: Text(t == null ? 'New trip' : 'Edit trip'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              initialValue: routeId,
              decoration: const InputDecoration(labelText: 'Route'),
              items: [for (final r in d.routes) DropdownMenuItem(value: r.id, child: Text(r.name))],
              onChanged: (v) => set(() => routeId = v!),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Departure time'),
              trailing: Text(time.format(dlg), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              onTap: () async {
                final p = await showTimePicker(context: dlg, initialTime: time);
                if (p != null) set(() => time = p);
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: dir,
              decoration: const InputDecoration(labelText: 'Direction'),
              items: const [
                DropdownMenuItem(value: 'INBOUND', child: Text('To campus (inbound)')),
                DropdownMenuItem(value: 'OUTBOUND', child: Text('From campus (outbound)')),
              ],
              onChanged: (v) => set(() => dir = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Trip type'),
              items: const [
                DropdownMenuItem(value: 'REGULAR', child: Text('Regular')),
                DropdownMenuItem(value: 'WEEKEND', child: Text('Weekend')),
                DropdownMenuItem(value: 'EXAM', child: Text('Exam')),
                DropdownMenuItem(value: 'SPECIAL', child: Text('Special')),
              ],
              onChanged: (v) => set(() => type = v!),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlg, false), child: const Text('Cancel')),
            FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
                onPressed: () => Navigator.pop(dlg, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || !c.mounted) return;
    final hhmm = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final done = await guarded(
        c,
        () => repo.saveTrip(
            id: t?.id, routeId: routeId, departure: hhmm, direction: dir, tripType: type, isActive: t?.isActive ?? true),
        ok: 'Trip saved.');
    if (done) {
      setState(() {
        _routeId = routeId;
        _rev++;
      });
    }
  }
}

class BusesSection extends StatefulWidget {
  const BusesSection({super.key});
  @override
  State<BusesSection> createState() => _BusesSectionState();
}

class _BusesSectionState extends State<BusesSection> {
  int _rev = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final repo = state.repo;
    final canEdit = state.session!.can(Perm.busManage);
    return AsyncView<List<Bus>>(
      key: ValueKey(_rev),
      load: repo.buses,
      builder: (c, buses, reload) => Scaffold(
        floatingActionButton: canEdit
            ? FloatingActionButton.extended(
                onPressed: () => _dialog(c, null), icon: const Icon(Icons.add), label: const Text('Bus'))
            : null,
        body: ListView(padding: const EdgeInsets.all(16), children: [
          for (final b in buses)
            Card(
              child: ListTile(
                leading: const Icon(Icons.directions_bus),
                title: Text('${b.fleetNumber} • ${b.registration}'),
                subtitle: Text('Capacity ${b.capacity}'),
                trailing: StatusChip(b.status),
                onTap: canEdit ? () => _dialog(c, b) : null,
              ),
            ),
          const SizedBox(height: 70),
        ]),
      ),
    );
  }

  Future<void> _dialog(BuildContext c, Bus? b) async {
    final repo = context.read<AppState>().repo;
    final fleet = TextEditingController(text: b?.fleetNumber);
    final reg = TextEditingController(text: b?.registration);
    final cap = TextEditingController(text: b?.capacity.toString() ?? '60');
    String status = b?.status ?? 'ACTIVE';
    final ok = await showDialog<bool>(
      context: c,
      builder: (dlg) => StatefulBuilder(
        builder: (dlg, set) => AlertDialog(
          title: Text(b == null ? 'New bus' : 'Edit bus'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: fleet, decoration: const InputDecoration(labelText: 'Fleet number')),
              const SizedBox(height: 12),
              TextField(controller: reg, decoration: const InputDecoration(labelText: 'Registration')),
              const SizedBox(height: 12),
              TextField(controller: cap, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Capacity')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                  DropdownMenuItem(value: 'MAINTENANCE', child: Text('Maintenance')),
                  DropdownMenuItem(value: 'RETIRED', child: Text('Retired')),
                ],
                onChanged: (v) => set(() => status = v!),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlg, false), child: const Text('Cancel')),
            FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
                onPressed: () => Navigator.pop(dlg, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    final f = fleet.text.trim(), r = reg.text.trim(), n = int.tryParse(cap.text.trim());
    fleet.dispose();
    reg.dispose();
    cap.dispose();
    if (ok != true || !c.mounted) return;
    if (f.isEmpty || r.isEmpty || n == null || n <= 0) {
      return snack(c, 'Fleet number, registration and a valid capacity are required', error: true);
    }
    final done = await guarded(c, () => repo.saveBus(id: b?.id, fleetNumber: f, registration: r, capacity: n, status: status), ok: 'Bus saved.');
    if (done) setState(() => _rev++);
  }
}
