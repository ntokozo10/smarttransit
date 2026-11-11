/// Build-time configuration.
///   flutter run --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=https://api.example.ac.za/api/v1
class AppConfig {
  static const useMock = bool.fromEnvironment('USE_MOCK', defaultValue: true);
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/api/v1', // Android emulator -> host
  );

  /// Academic year used for route-residence lookups.
  static int get academicYear => DateTime.now().year;
}
