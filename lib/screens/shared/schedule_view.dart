import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class _Data {
  _Data(this.routes, this.trips);
  final List<TransportRoute> routes;
  final List<Trip> trips;
}

/// Read-only timetable grouped by direction, with a route picker.
class ScheduleView extends StatefulWidget {
  const ScheduleView({super.key, this.initialRouteId, this.lockToRoute = false});
  final int? initialRouteId;
  final bool lockToRoute;
  @override
  State<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends State<ScheduleView> {
  int? _routeId;

  @override
  void initState() {
    super.initState();
    _routeId = widget.initialRouteId;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    return AsyncView<_Data>(
      load: () async => _Data(await repo.routes(), await repo.trips()),
      builder: (c, d, reload) {
        final routes = d.routes.where((r) => r.isActive).toList();
        _routeId ??= routes.isEmpty ? null : routes.first.id;
        final trips = d.trips.where((t) => t.routeId == _routeId && t.isActive).toList();
        Widget section(String dir, String title, IconData icon) {
          final l = trips.where((t) => t.direction == dir).toList();
          if (l.isEmpty) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle(title),
            Card(
              child: Column(children: [
                for (final t in l)
                  ListTile(
                    leading: Icon(icon),
                    title: Text(t.departure, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    trailing: t.tripType == 'REGULAR' ? null : Chip(label: Text(titleCase(t.tripType))),
                  ),
              ]),
            ),
          ]);
        }

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<int>(
              initialValue: _routeId,
              decoration: const InputDecoration(labelText: 'Route', prefixIcon: Icon(Icons.alt_route)),
              items: [for (final r in routes) DropdownMenuItem(value: r.id, child: Text(r.name))],
              onChanged: (v) => setState(() => _routeId = v),
            ),
            if (trips.isEmpty) const EmptyState(Icons.schedule, 'No trips scheduled for this route.'),
            section('INBOUND', 'To campus', Icons.north_east),
            section('OUTBOUND', 'From campus', Icons.south_west),
          ],
        );
      },
    );
  }
}
