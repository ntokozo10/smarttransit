import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/mock_repository.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../shared/alerts_view.dart';
import 'scanner_screen.dart';

class DriverShell extends StatefulWidget {
  const DriverShell({super.key});
  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    final pending = context.watch<AppState>().pending.length;
    final tabs = [const _TripsTab(), const _HistoryTab(), const AlertsView(), const _DriverProfile()];
    return Scaffold(
      appBar: AppBar(title: Text(['Today\'s trips', 'Scan history', 'Alerts', 'Profile'][_tab])),
      body: tabs[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.directions_bus_outlined), selectedIcon: Icon(Icons.directions_bus), label: 'Trips'),
          NavigationDestination(
              icon: Badge(isLabelVisible: pending > 0, label: Text('$pending'), child: const Icon(Icons.history)),
              label: 'History'),
          const NavigationDestination(icon: Icon(Icons.notifications_outlined), label: 'Alerts'),
          const NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

class _TripData {
  _TripData(this.trips, this.routes, this.buses);
  final List<Trip> trips;
  final List<TransportRoute> routes;
  final List<Bus> buses;
}

class _TripsTab extends StatefulWidget {
  const _TripsTab();
  @override
  State<_TripsTab> createState() => _TripsTabState();
}

class _TripsTabState extends State<_TripsTab> {
  int? _busId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final repo = state.repo;
    return AsyncView<_TripData>(
      load: () async => _TripData(await repo.myDriverTrips(), await repo.routes(), await repo.buses()),
      builder: (c, d, reload) {
        final buses = d.buses.where((b) => b.status == 'ACTIVE').toList();
        String route(int id) => d.routes.firstWhere((r) => r.id == id).name;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (state.pending.isNotEmpty)
              Card(
                color: warnColor.withValues(alpha: .12),
                child: ListTile(
                  leading: const Icon(Icons.cloud_off, color: warnColor),
                  title: Text('${state.pending.length} scan(s) waiting to sync'),
                  trailing: state.syncing
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : TextButton(
                          onPressed: () async {
                            final n = await state.syncPending();
                            if (c.mounted) snack(c, n > 0 ? 'Synced $n scan(s).' : 'Still offline — will retry.');
                          },
                          child: const Text('Sync now')),
                ),
              ),
            DropdownButtonFormField<int>(
              initialValue: _busId,
              decoration: const InputDecoration(labelText: 'Bus', prefixIcon: Icon(Icons.directions_bus)),
              items: [for (final b in buses) DropdownMenuItem(value: b.id, child: Text('${b.fleetNumber} • ${b.registration}'))],
              onChanged: (v) => setState(() => _busId = v),
            ),
            const SectionTitle('Assigned trips'),
            if (d.trips.isEmpty) const EmptyState(Icons.event_busy, 'No trips assigned to you.'),
            for (final t in d.trips)
              Card(
                child: ListTile(
                  leading: Icon(t.direction == 'INBOUND' ? Icons.north_east : Icons.south_west),
                  title: Text('${t.departure}  •  ${route(t.routeId)}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${t.direction == 'INBOUND' ? 'To campus' : 'From campus'} • ${titleCase(t.tripType)}'),
                  trailing: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(90, 40)),
                    onPressed: _busId == null
                        ? null
                        : () => Navigator.push(
                            c,
                            MaterialPageRoute(
                                builder: (_) => ScannerScreen(
                                    trip: t, routeName: route(t.routeId), busId: _busId!))),
                    child: const Text('Scan'),
                  ),
                ),
              ),
            if (_busId == null && d.trips.isNotEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Select a bus to start scanning.', textAlign: TextAlign.center),
              ),
          ],
        );
      },
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return AsyncView<List<ScanLog>>(
      load: () => state.repo.scanLogs(mine: true),
      builder: (c, logs, reload) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (state.pending.isNotEmpty) ...[
            const SectionTitle('Pending sync'),
            for (final p in state.pending)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined, color: warnColor),
                  title: Text('Trip ${p.tripId} • bus ${p.busId}'),
                  subtitle: Text(fmtDateTime(p.scannedAt.toLocal())),
                  trailing: const StatusChip('PENDING'),
                ),
              ),
          ],
          const SectionTitle('Recent scans'),
          if (logs.isEmpty) const EmptyState(Icons.qr_code_scanner, 'No scans yet.'),
          for (final l in logs)
            Card(
              child: ListTile(
                leading: Icon(l.status == 'ACCEPTED' ? Icons.check_circle : Icons.cancel, color: statusColor(l.status)),
                title: Text(l.studentName),
                subtitle: Text('${fmtDateTime(l.scanTime)}${l.reason == null ? '' : '\n${l.reason}'}'),
                isThreeLine: l.reason != null,
                trailing: StatusChip(l.status),
              ),
            ),
        ],
      ),
    );
  }
}

class _DriverProfile extends StatefulWidget {
  const _DriverProfile();
  @override
  State<_DriverProfile> createState() => _DriverProfileState();
}

class _DriverProfileState extends State<_DriverProfile> {
  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final u = state.session!.user;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            CircleAvatar(radius: 32, backgroundColor: wsuBlue, child: Text('${u.firstName[0]}${u.lastName[0]}', style: const TextStyle(color: Colors.white, fontSize: 22))),
            const SizedBox(height: 12),
            Text(u.fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            KeyValue('Email', u.email),
            KeyValue('Phone', u.phone ?? '—'),
            const KeyValue('Role', 'Driver'),
          ]),
        ),
      ),
      if (state.repo is MockRepository)
        SwitchListTile(
          title: const Text('Simulate offline (demo)'),
          subtitle: const Text('Scans are queued and synced later'),
          value: state.repo.simulateOffline,
          onChanged: (v) => setState(() => state.repo.simulateOffline = v),
        ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        icon: const Icon(Icons.logout),
        label: const Text('Sign out'),
        onPressed: state.logout,
      ),
    ]);
  }
}
