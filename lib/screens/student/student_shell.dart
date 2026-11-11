import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../shared/schedule_view.dart';
import '../shared/alerts_view.dart';

class StudentShell extends StatefulWidget {
  const StudentShell({super.key});
  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  int _tab = 0;
  // Bumped to force child tabs to reload after an action.
  int _rev = 0;

  @override
  Widget build(BuildContext context) {
    final titles = ['SmartTransit', 'My pass', 'Schedule', 'Alerts', 'Profile'];
    final tabs = <Widget>[
      _HomeTab(key: ValueKey('h$_rev'), onChanged: () => setState(() => _rev++), goPass: () => setState(() => _tab = 1)),
      _PassTab(key: ValueKey('p$_rev')),
      const _ScheduleTab(),
      const AlertsView(showNotifications: true),
      const _ProfileTab(),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(titles[_tab])),
      body: tabs[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.qr_code_2), label: 'Pass'),
          NavigationDestination(icon: Icon(Icons.schedule), label: 'Schedule'),
          NavigationDestination(icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications), label: 'Alerts'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- home
class _HomeData {
  _HomeData(this.apps, this.pass);
  final List<Application> apps;
  final TransportPass? pass;
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({super.key, required this.onChanged, required this.goPass});
  final VoidCallback onChanged, goPass;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    final user = context.read<AppState>().session!.user;
    return AsyncView<_HomeData>(
      load: () async => _HomeData(await repo.myApplications(), await repo.myPass()),
      builder: (c, d, reload) {
        final latest = d.apps.isEmpty ? null : d.apps.first;
        final canApply = latest == null || latest.status == AppStatus.rejected;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text('Hello, ${user.firstName} 👋',
                style: Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text('Academic year ${AppConfig.academicYear}', style: TextStyle(color: Theme.of(c).colorScheme.outline)),
            const SizedBox(height: 12),
            if (d.pass != null) _PassSummary(d.pass!, onTap: goPass),
            if (latest != null) ...[
              const SectionTitle('Application'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(latest.residenceName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                      StatusChip(latest.status),
                    ]),
                    const SizedBox(height: 8),
                    KeyValue('Applied', fmtDateTime(latest.appliedAt)),
                    if (latest.routeName != null) KeyValue('Route', latest.routeName!),
                    if (latest.reviewedAt != null) KeyValue('Reviewed', fmtDateTime(latest.reviewedAt!)),
                    if (latest.rejectionReason != null) KeyValue('Reason', latest.rejectionReason!),
                    const SizedBox(height: 8),
                    _Progress(latest.status),
                  ]),
                ),
              ),
            ],
            if (canApply) ...[
              const SizedBox(height: 12),
              if (latest == null)
                const EmptyState(Icons.directions_bus_outlined,
                    'You have not applied for university transport yet.'),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: Text(latest == null ? 'Apply for transport' : 'Apply again'),
                onPressed: () async {
                  final done = await Navigator.push<bool>(
                      c, MaterialPageRoute(builder: (_) => const ApplyScreen()));
                  if (done == true) onChanged();
                },
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress(this.status);
  final String status;
  @override
  Widget build(BuildContext context) {
    final rejected = status == AppStatus.rejected;
    final step = status == AppStatus.approved || rejected ? 3 : 2;
    final labels = ['Submitted', 'Under review', rejected ? 'Rejected' : 'Approved'];
    return Row(children: [
      for (var i = 0; i < 3; i++) ...[
        Expanded(
          child: Column(children: [
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: i < step
                    ? (rejected && i == 2 ? badColor : Theme.of(context).colorScheme.primary)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 4),
            Text(labels[i], style: const TextStyle(fontSize: 11)),
          ]),
        ),
        if (i < 2) const SizedBox(width: 6),
      ]
    ]);
  }
}

class _PassSummary extends StatelessWidget {
  const _PassSummary(this.pass, {required this.onTap});
  final TransportPass pass;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primaryContainer,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.all(16),
        leading: Icon(Icons.confirmation_number_outlined, size: 36, color: cs.primary),
        title: Text('${pass.routeName} route', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        subtitle: Text('${pass.residenceName}\nValid until ${fmtDate(pass.validTo)}'),
        isThreeLine: true,
        trailing: StatusChip(pass.isUsable ? 'ACTIVE' : pass.status == 'ACTIVE' ? 'EXPIRED' : pass.status),
      ),
    );
  }
}

// ---------------------------------------------------------------- apply
class ApplyScreen extends StatefulWidget {
  const ApplyScreen({super.key});
  @override
  State<ApplyScreen> createState() => _ApplyScreenState();
}

class _ApplyScreenState extends State<ApplyScreen> {
  late final Repository repo = context.read<AppState>().repo;
  late final Future<(List<Residence>, List<Assignment>, List<TransportRoute>)> _data = _load();
  int? _residenceId;
  bool _busy = false;

  Future<(List<Residence>, List<Assignment>, List<TransportRoute>)> _load() async {
    final r = await repo.residences();
    final a = await repo.assignments(year: AppConfig.academicYear);
    final t = await repo.routes();
    return (r.where((x) => x.isActive).toList(), a, t);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Apply for transport')),
      body: FutureBuilder(
        future: _data,
        builder: (c, s) {
          if (s.hasError) return ErrorView(s.error!);
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final (residences, asg, routes) = s.data!;
          Assignment? mine;
          if (_residenceId != null) {
            for (final a in asg) {
              if (a.residenceId == _residenceId && a.isActive) mine = a;
            }
          }
          final route = mine == null ? null : routes.firstWhere((r) => r.id == mine!.routeId);
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Text('Choose the residence where you stay. Your bus route is set by the transport office for the current academic year.'),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _residenceId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Residence', prefixIcon: Icon(Icons.apartment)),
              items: [for (final r in residences) DropdownMenuItem(value: r.id, child: Text(r.name))],
              onChanged: (v) => setState(() => _residenceId = v),
            ),
            const SizedBox(height: 16),
            if (_residenceId != null)
              Card(
                color: route == null
                    ? badColor.withValues(alpha: .08)
                    : Theme.of(c).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: route == null
                      ? Text('No route has been assigned to this residence for ${AppConfig.academicYear} yet. You cannot apply until the transport office assigns one.')
                      : Row(children: [
                          const Icon(Icons.alt_route, size: 32),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Your route'),
                            Text(route.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                          ])),
                        ]),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: (_residenceId == null || route == null || _busy)
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      final ok = await guarded(c, () => repo.submitApplication(_residenceId!),
                          ok: 'Application submitted — it is now under review.');
                      if (!mounted) return;
                      setState(() => _busy = false);
                      // ignore: use_build_context_synchronously
                      if (ok) Navigator.pop(context, true);
                    },
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Submit application'),
            ),
          ]);
        },
      ),
    );
  }
}

// ----------------------------------------------------------------- pass
class _PassTab extends StatelessWidget {
  const _PassTab({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    final user = context.read<AppState>().session!.user;
    return AsyncView<TransportPass?>(
      load: repo.myPass,
      builder: (c, p, reload) {
        if (p == null) {
          return ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
            EmptyState(Icons.qr_code_2, 'You do not have a transport pass yet.\nApply on the Home tab; your pass appears here once approved.'),
          ]);
        }
        final usable = p.isUsable;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  Text(user.fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  Text(user.studentNumber ?? '', style: TextStyle(color: Theme.of(c).colorScheme.outline)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Opacity(
                      opacity: usable ? 1 : .25,
                      child: QrImageView(data: p.qrPayload, size: 220, backgroundColor: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 12),
                  StatusChip(usable ? 'ACTIVE' : (p.status == 'ACTIVE' ? 'EXPIRED' : p.status)),
                  const SizedBox(height: 8),
                  Text('Show this code to the driver when boarding.',
                      textAlign: TextAlign.center, style: TextStyle(color: Theme.of(c).colorScheme.outline)),
                ]),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  KeyValue('Route', p.routeName),
                  KeyValue('Residence', p.residenceName),
                  KeyValue('Academic year', '${p.academicYear}'),
                  KeyValue('Valid from', fmtDate(p.validFrom)),
                  KeyValue('Valid to', fmtDate(p.validTo)),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------- schedule
class _ScheduleTab extends StatelessWidget {
  const _ScheduleTab();
  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    return AsyncView<TransportPass?>(
      load: repo.myPass,
      builder: (c, p, reload) => ScheduleView(initialRouteId: p?.routeId, lockToRoute: false),
    );
  }
}

// -------------------------------------------------------------- profile
class _ProfileTab extends StatelessWidget {
  const _ProfileTab();
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
            KeyValue('Student no.', u.studentNumber ?? '—'),
            KeyValue('Email', u.email),
            KeyValue('Phone', u.phone ?? '—'),
            KeyValue('Funding', u.fundingStatus ?? '—'),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        icon: const Icon(Icons.logout),
        label: const Text('Sign out'),
        onPressed: () => state.logout(),
      ),
    ]);
  }
}
