import '../models/models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => message;
}

/// Raised when a privileged account must supply an MFA code.
class MfaRequiredException extends ApiException {
  MfaRequiredException() : super('Verification code required', code: 'MFA_REQUIRED');
}

/// Raised when the server cannot be reached (driver app queues scans).
class NetworkException extends ApiException {
  NetworkException([super.message = 'No connection to the server']);
}

/// Single data boundary for the UI. Two implementations:
///  - MockRepository: in-memory backend for demos/offline development
///  - HttpRepository: the Node/Express REST API from the design document
abstract class Repository {
  /// Mock-only switch used to demo the driver offline queue.
  bool simulateOffline = false;

  // --- auth
  Future<Session?> restoreSession();
  Future<Session> login(String email, String password, {String? mfaCode});
  Future<void> logout();

  // --- transport configuration
  Future<List<TransportRoute>> routes();
  Future<TransportRoute> saveRoute({
    int? id,
    required String name,
    String? description,
    required bool isActive,
  });
  Future<List<Residence>> residences();
  Future<Residence> saveResidence({
    int? id,
    required String name,
    String? location,
    required bool isActive,
  });
  Future<List<Assignment>> assignments({int? year});
  Future<Assignment> saveAssignment({
    required int residenceId,
    required int routeId,
    required int year,
  });
  Future<List<Trip>> trips({int? routeId});
  Future<Trip> saveTrip({
    int? id,
    required int routeId,
    required String departure,
    required String direction,
    required String tripType,
    required bool isActive,
  });
  Future<List<Trip>> myDriverTrips();
  Future<List<Bus>> buses();
  Future<Bus> saveBus({
    int? id,
    required String fleetNumber,
    required String registration,
    required int capacity,
    required String status,
  });

  // --- applications & passes
  Future<List<Application>> applications({String? status});
  Future<List<Application>> myApplications();
  Future<Application> submitApplication(int residenceId);
  Future<Application> approveApplication(int id);
  Future<Application> rejectApplication(int id, String reason);
  Future<TransportPass?> myPass();

  // --- scanning
  Future<ScanResult> submitScan(ScanRequest request);
  Future<List<ScanLog>> scanLogs({bool mine = false});

  // --- communication
  Future<List<ServiceAlert>> alerts();
  Future<ServiceAlert> createAlert({
    required String title,
    required String message,
    required String severity,
    int? routeId,
  });
  Future<void> deactivateAlert(int id);
  Future<List<AppNotification>> notifications();

  // --- reporting & administration
  Future<UsageReport> usageReport();
  Future<List<AppUser>> users();
  Future<AppUser> updateUser(int id, {String? status, List<AppRole>? roles});
  Future<List<AuditLog>> auditLogs();
  Future<List<SessionRecord>> sessions();
  Future<void> revokeSession(int id);
}
