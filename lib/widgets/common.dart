import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';

void snack(BuildContext c, String msg, {bool error = false}) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? badColor : null,
      behavior: SnackBarBehavior.floating,
    ));
}

/// Runs [job], shows errors as a snackbar, returns true on success.
Future<bool> guarded(BuildContext c, Future<void> Function() job, {String? ok}) async {
  try {
    await job();
    if (ok != null && c.mounted) snack(c, ok);
    return true;
  } catch (e) {
    if (c.mounted) snack(c, e.toString(), error: true);
    return false;
  }
}

Color statusColor(String s) {
  switch (s.toUpperCase()) {
    case 'APPROVED':
    case 'ACTIVE':
    case 'ACCEPTED':
    case 'SYNCED':
    case 'INFO':
      return okColor;
    case 'UNDER_REVIEW':
    case 'SUBMITTED':
    case 'WARNING':
    case 'MAINTENANCE':
    case 'DUPLICATE':
    case 'PENDING':
      return warnColor;
    default:
      return badColor;
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(titleCase(status),
          style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Row(children: [
          Expanded(
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700))),
          if (trailing != null) trailing!,
        ]),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ]),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView(this.error, {super.key, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 44, color: badColor),
            const SizedBox(height: 12),
            Text(error.toString(), textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ]),
        ),
      );
}

/// Loads async data, shows spinner / error / pull-to-refresh content.
/// [builder] must return a scrollable (e.g. ListView).
class AsyncView<T> extends StatefulWidget {
  const AsyncView({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext, T data, Future<void> Function() reload) builder;
  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _f;
  @override
  void initState() {
    super.initState();
    _f = widget.load();
  }

  Future<void> _reload() async {
    final f = widget.load();
    setState(() => _f = f);
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _f,
        builder: (c, s) {
          if (s.hasError) return ErrorView(s.error!, onRetry: _reload);
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          return RefreshIndicator(
            onRefresh: _reload,
            child: widget.builder(c, s.data as T, _reload),
          );
        },
      );
}

class KeyValue extends StatelessWidget {
  const KeyValue(this.k, this.v, {super.key});
  final String k, v;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 120,
              child: Text(k,
                  style: TextStyle(color: Theme.of(context).colorScheme.outline))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w500))),
        ]),
      );
}

Future<bool> confirm(BuildContext c, String title, String body, {String ok = 'Confirm'}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
            onPressed: () => Navigator.pop(c, true),
            child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}
