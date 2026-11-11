import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/permissions.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import 'alerts_admin.dart';
import 'applications_section.dart';
import 'audit_sessions_users.dart';
import 'dashboard_section.dart';
import 'network_section.dart';
import 'trips_buses_section.dart';

class _Section {
  _Section(this.title, this.icon, this.builder, this.allowed);
  final String title;
  final IconData icon;
  final Widget Function() builder;
  final bool Function(Session) allowed;
}

/// Operations console for officers, managers and super admins.
/// Sections are shown only when the user's permissions allow them.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _i = 0;

  static final _all = <_Section>[
    _Section('Dashboard', Icons.dashboard_outlined, () => const DashboardSection(), (s) => s.can(Perm.reportView)),
    _Section('Applications', Icons.assignment_outlined, () => const ApplicationsSection(), (s) => s.can(Perm.applicationReview)),
    _Section('Routes & residences', Icons.alt_route, () => const NetworkSection(), (s) => s.can(Perm.configView)),
    _Section('Trips', Icons.schedule, () => const TripsSection(), (s) => s.can(Perm.configView)),
    _Section('Buses', Icons.directions_bus_outlined, () => const BusesSection(), (s) => s.can(Perm.busView)),
    _Section('Service alerts', Icons.campaign_outlined, () => const AlertsAdminSection(), (s) => s.can(Perm.alertManage)),
    _Section('Scan log', Icons.qr_code_scanner, () => const ScanLogSection(), (s) => s.can(Perm.reportView)),
    _Section('Users & roles', Icons.group_outlined, () => const UsersSection(), (s) => s.can(Perm.userManage)),
    _Section('Audit log', Icons.fact_check_outlined, () => const AuditSection(), (s) => s.canAny([Perm.auditView, Perm.auditViewLimited])),
    _Section('Sessions', Icons.devices_outlined, () => const SessionsSection(), (s) => s.can(Perm.sessionManage)),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final session = state.session!;
    final sections = _all.where((s) => s.allowed(session)).toList();
    if (_i >= sections.length) _i = 0;
    final current = sections[_i];
    return Scaffold(
      appBar: AppBar(title: Text(current.title)),
      drawer: Drawer(
        child: SafeArea(
          child: Column(children: [
            UserAccountsDrawerHeader(
              accountName: Text(session.user.fullName),
              accountEmail: Text('${session.primaryRole.label} • ${session.user.email}'),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                child: Text('${session.user.firstName[0]}${session.user.lastName[0]}'),
              ),
            ),
            Expanded(
              child: ListView(children: [
                for (var k = 0; k < sections.length; k++)
                  ListTile(
                    leading: Icon(sections[k].icon),
                    title: Text(sections[k].title),
                    selected: k == _i,
                    onTap: () {
                      setState(() => _i = k);
                      Navigator.pop(context);
                    },
                  ),
              ]),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: state.logout,
            ),
          ]),
        ),
      ),
      body: KeyedSubtree(key: ValueKey(current.title), child: current.builder()),
    );
  }
}
