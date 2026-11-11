import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'data/http_repository.dart';
import 'data/mock_repository.dart';
import 'data/repository.dart';
import 'screens/admin/admin_shell.dart';
import 'screens/driver/driver_shell.dart';
import 'screens/login_screen.dart';
import 'screens/student/student_shell.dart';
import 'state/app_state.dart';
import 'models/models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final Repository repo =
      AppConfig.useMock ? MockRepository() : HttpRepository(AppConfig.apiBaseUrl);
  runApp(ChangeNotifierProvider(
    create: (_) => AppState(repo)..boot(),
    child: const SmartTransitApp(),
  ));
}

class SmartTransitApp extends StatelessWidget {
  const SmartTransitApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'IWS SmartTransit',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const _Gate(),
      );
}

/// Chooses the shell from the signed-in user's highest role.
class _Gate extends StatelessWidget {
  const _Gate();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (s.booting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final session = s.session;
    if (session == null) return const LoginScreen();
    switch (session.primaryRole) {
      case AppRole.student:
        return const StudentShell();
      case AppRole.driver:
        return const DriverShell();
      case AppRole.officer:
      case AppRole.manager:
      case AppRole.superAdmin:
        return const AdminShell();
    }
  }
}
