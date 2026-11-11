import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

// ----------------------------------------------------------------- audit
class AuditSection extends StatelessWidget {
  const AuditSection({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    return AsyncView<List<AuditLog>>(
      load: repo.auditLogs,
      builder: (c, logs, reload) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (logs.isEmpty) const EmptyState(Icons.fact_check_outlined, 'No audit entries.'),
          for (final l in logs)
            Card(
              child: ListTile(
                dense: true,
                title: Text(titleCase(l.action), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    '${l.userName} • ${l.entityType}${l.entityId == null ? '' : ' #${l.entityId}'}'
                    '${l.details == null ? '' : '\n${l.details}'}\n${fmtDateTime(l.createdAt)}'
                    '${l.ipAddress == null ? '' : ' • ${l.ipAddress}'}'),
                isThreeLine: true,
              ),
            ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- sessions
class SessionsSection extends StatefulWidget {
  const SessionsSection({super.key});
  @override
  State<SessionsSection> createState() => _SessionsSectionState();
}

class _SessionsSectionState extends State<SessionsSection> {
  int _rev = 0;
  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    return AsyncView<List<SessionRecord>>(
      key: ValueKey(_rev),
      load: repo.sessions,
      builder: (c, list, reload) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          for (final s in list)
            Card(
              child: ListTile(
                leading: Icon(s.isActive ? Icons.devices : Icons.devices_other, color: s.isActive ? null : Theme.of(c).disabledColor),
                title: Text(s.userName),
                subtitle: Text('${s.ipAddress ?? ''} • ${s.userAgent ?? ''}\nStarted ${fmtDateTime(s.createdAt)}'),
                isThreeLine: true,
                trailing: s.isActive
                    ? TextButton(
                        onPressed: () async {
                          if (!await confirm(c, 'Revoke session?', '${s.userName} will be signed out.', ok: 'Revoke')) return;
                          if (!c.mounted) return;
                          final ok = await guarded(c, () => repo.revokeSession(s.id), ok: 'Session revoked.');
                          if (ok) setState(() => _rev++);
                        },
                        child: const Text('Revoke'))
                    : const StatusChip('REVOKED'),
              ),
            ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- users
class UsersSection extends StatefulWidget {
  const UsersSection({super.key});
  @override
  State<UsersSection> createState() => _UsersSectionState();
}

class _UsersSectionState extends State<UsersSection> {
  int _rev = 0;
  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    return AsyncView<List<AppUser>>(
      key: ValueKey(_rev),
      load: repo.users,
      builder: (c, users, reload) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          for (final u in users)
            Card(
              child: ListTile(
                title: Text(u.fullName),
                subtitle: Text('${u.email}\n${u.roles.map((r) => r.label).join(', ')}'),
                isThreeLine: true,
                trailing: Switch(
                  value: u.isActive,
                  onChanged: (v) async {
                    final ok = await guarded(c, () => repo.updateUser(u.id, status: v ? 'ACTIVE' : 'DISABLED'));
                    if (ok) setState(() => _rev++);
                  },
                ),
                onTap: () => _roles(c, u),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _roles(BuildContext c, AppUser u) async {
    final repo = context.read<AppState>().repo;
    final sel = {...u.roles};
    final ok = await showDialog<bool>(
      context: c,
      builder: (dlg) => StatefulBuilder(
        builder: (dlg, set) => AlertDialog(
          title: Text('Roles — ${u.fullName}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final r in AppRole.values)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r.label),
                subtitle: r.requiresMfa ? const Text('Requires MFA') : null,
                value: sel.contains(r),
                onChanged: (v) => set(() => v == true ? sel.add(r) : sel.remove(r)),
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
    final done = await guarded(c, () => repo.updateUser(u.id, roles: sel.toList()), ok: 'Roles updated.');
    if (done) setState(() => _rev++);
  }
}
