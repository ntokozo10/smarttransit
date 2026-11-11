/// Domain models mirroring the Phase 1 PostgreSQL schema (snake_case JSON).
library;

enum AppRole { student, driver, officer, manager, superAdmin }

extension AppRoleX on AppRole {
  String get code => switch (this) {
        AppRole.student => 'STUDENT',
        AppRole.driver => 'DRIVER',
        AppRole.officer => 'TRANSPORT_OFFICER',
        AppRole.manager => 'TRANSPORT_MANAGER',
        AppRole.superAdmin => 'SUPER_ADMIN',
      };
  String get label => switch (this) {
        AppRole.student => 'Student',
        AppRole.driver => 'Driver',
        AppRole.officer => 'Transport Officer',
        AppRole.manager => 'Transport Manager',
        AppRole.superAdmin => 'Super Admin',
      };

  /// Privileged roles must pass MFA (design doc section 7).
  bool get requiresMfa =>
      this == AppRole.officer ||
      this == AppRole.manager ||
      this == AppRole.superAdmin;
}

AppRole roleFromCode(String s) {
  switch (s.toUpperCase()) {
    case 'DRIVER':
      return AppRole.driver;
    case 'TRANSPORT_OFFICER':
      return AppRole.officer;
    case 'TRANSPORT_MANAGER':
      return AppRole.manager;
    case 'SUPER_ADMIN':
      return AppRole.superAdmin;
    default:
      return AppRole.student;
  }
}

DateTime _dt(dynamic v) => DateTime.parse(v.toString()).toLocal();
DateTime? _dtn(dynamic v) => v == null ? null : _dt(v);
int _i(dynamic v) => v is int ? v : int.parse(v.toString());

class AppUser {
  AppUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    this.phone,
    this.status = 'ACTIVE',
    required this.roles,
    this.studentNumber,
    this.fundingStatus,
  });
  final int id;
  final String email, firstName, lastName;
  final String? phone, studentNumber, fundingStatus;
  String status;
  List<AppRole> roles;

  String get fullName => '$firstName $lastName';
  bool get isActive => status == 'ACTIVE';

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: _i(j['user_id']),
        email: j['email'],
        firstName: j['first_name'],
        lastName: j['last_name'],
        phone: j['phone'],
        status: j['status'] ?? 'ACTIVE',
        roles: ((j['roles'] ?? []) as List)
            .map((r) => roleFromCode(r.toString()))
            .toList(),
        studentNumber: j['student_number'],
        fundingStatus: j['funding_status'],
      );
}

class Session {
  Session({required this.user, required this.permissions});
  final AppUser user;
  final Set<String> permissions;

  bool can(String permission) => permissions.contains(permission);
  bool canAny(Iterable<String> p) => p.any(permissions.contains);

  /// Highest-privilege role decides which shell is shown.
  AppRole get primaryRole {
    const order = [
      AppRole.superAdmin,
      AppRole.manager,
      AppRole.officer,
      AppRole.driver,
      AppRole.student,
    ];
    return order.firstWhere(user.roles.contains, orElse: () => AppRole.student);
  }
}

class TransportRoute {
  TransportRoute({
    required this.id,
    required this.name,
    this.description,
    this.isActive = true,
  });
  final int id;
  final String name;
  final String? description;
  final bool isActive;
  factory TransportRoute.fromJson(Map<String, dynamic> j) => TransportRoute(
        id: _i(j['route_id']),
        name: j['route_name'],
        description: j['description'],
        isActive: j['is_active'] ?? true,
      );
}

class Residence {
  Residence({
    required this.id,
    required this.name,
    this.location,
    this.isActive = true,
  });
  final int id;
  final String name;
  final String? location;
  final bool isActive;
  factory Residence.fromJson(Map<String, dynamic> j) => Residence(
        id: _i(j['residence_id']),
        name: j['residence_name'],
        location: j['location'],
        isActive: j['is_active'] ?? true,
      );
}

class Assignment {
  Assignment({
    required this.id,
    required this.residenceId,
    required this.routeId,
    required this.academicYear,
    this.effectiveFrom,
    this.effectiveTo,
    this.isActive = true,
  });
  final int id, residenceId, routeId, academicYear;
  final DateTime? effectiveFrom, effectiveTo;
  final bool isActive;
  factory Assignment.fromJson(Map<String, dynamic> j) => Assignment(
        id: _i(j['assignment_id']),
        residenceId: _i(j['residence_id']),
        routeId: _i(j['route_id']),
        academicYear: _i(j['academic_year']),
        effectiveFrom: _dtn(j['effective_from']),
        effectiveTo: _dtn(j['effective_to']),
        isActive: j['is_active'] ?? true,
      );
}

class Trip {
  Trip({
    required this.id,
    required this.routeId,
    required this.departure,
    required this.direction,
    this.tripType = 'REGULAR',
    this.isActive = true,
  });
  final int id, routeId;

  /// 'HH:mm'
  final String departure;

  /// INBOUND | OUTBOUND
  final String direction;
  final String tripType;
  final bool isActive;
  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: _i(j['trip_id']),
        routeId: _i(j['route_id']),
        departure: j['departure_time'].toString().substring(0, 5),
        direction: j['direction'],
        tripType: j['trip_type'] ?? 'REGULAR',
        isActive: j['is_active'] ?? true,
      );
}

class Bus {
  Bus({
    required this.id,
    required this.fleetNumber,
    required this.registration,
    required this.capacity,
    this.status = 'ACTIVE',
  });
  final int id, capacity;
  final String fleetNumber, registration, status;
  factory Bus.fromJson(Map<String, dynamic> j) => Bus(
        id: _i(j['bus_id']),
        fleetNumber: j['fleet_number'],
        registration: j['registration_number'],
        capacity: _i(j['capacity']),
        status: j['status'] ?? 'ACTIVE',
      );
}

/// Application workflow states.
class AppStatus {
  static const submitted = 'SUBMITTED';
  static const underReview = 'UNDER_REVIEW';
  static const approved = 'APPROVED';
  static const rejected = 'REJECTED';
  static const all = [underReview, approved, rejected];
}

class Application {
  Application({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.studentNumber,
    required this.residenceId,
    required this.residenceName,
    required this.status,
    required this.appliedAt,
    this.routeName,
    this.reviewedBy,
    this.reviewedAt,
    this.rejectionReason,
  });
  final int id, studentId, residenceId;
  final String studentName, studentNumber, residenceName;
  final String? routeName, reviewedBy, rejectionReason;
  final String status;
  final DateTime appliedAt;
  final DateTime? reviewedAt;

  factory Application.fromJson(Map<String, dynamic> j) => Application(
        id: _i(j['application_id']),
        studentId: _i(j['student_id']),
        studentName: j['student_name'] ?? '',
        studentNumber: j['student_number'] ?? '',
        residenceId: _i(j['residence_id']),
        residenceName: j['residence_name'] ?? '',
        routeName: j['route_name'],
        status: j['status'],
        appliedAt: _dt(j['applied_at']),
        reviewedBy: j['reviewed_by_name'],
        reviewedAt: _dtn(j['reviewed_at']),
        rejectionReason: j['rejection_reason'],
      );
}

class TransportPass {
  TransportPass({
    required this.id,
    required this.studentId,
    required this.routeId,
    required this.routeName,
    required this.residenceName,
    required this.academicYear,
    required this.validFrom,
    required this.validTo,
    required this.status,
    required this.token,
  });
  final int id, studentId, routeId, academicYear;
  final String routeName, residenceName, status;

  /// Opaque pass token shown as a QR code. Only its hash is stored server-side.
  final String token;
  final DateTime validFrom, validTo;

  bool get isUsable {
    final now = DateTime.now();
    return status == 'ACTIVE' &&
        !now.isBefore(validFrom) &&
        !now.isAfter(validTo.add(const Duration(days: 1)));
  }

  String get qrPayload => 'WSUST:$token';

  factory TransportPass.fromJson(Map<String, dynamic> j) => TransportPass(
        id: _i(j['pass_id']),
        studentId: _i(j['student_id']),
        routeId: _i(j['route_id']),
        routeName: j['route_name'] ?? '',
        residenceName: j['residence_name'] ?? '',
        academicYear: _i(j['academic_year']),
        validFrom: _dt(j['valid_from']),
        validTo: _dt(j['valid_to']),
        status: j['status'],
        token: j['pass_token'],
      );
}

class ScanRequest {
  ScanRequest({
    required this.token,
    required this.tripId,
    required this.busId,
    required this.scannedAt,
    required this.clientId,
  });
  final String token, clientId;
  final int tripId, busId;
  final DateTime scannedAt;

  Map<String, dynamic> toJson() => {
        'token': token,
        'trip_id': tripId,
        'bus_id': busId,
        'scanned_at': scannedAt.toUtc().toIso8601String(),
        'client_id': clientId,
      };
  factory ScanRequest.fromJson(Map<String, dynamic> j) => ScanRequest(
        token: j['token'],
        tripId: _i(j['trip_id']),
        busId: _i(j['bus_id']),
        scannedAt: _dt(j['scanned_at']),
        clientId: j['client_id'],
      );
}

class ScanResult {
  ScanResult({
    required this.accepted,
    required this.status,
    required this.message,
    this.studentName,
    this.studentNumber,
  });
  final bool accepted;
  final String status, message;
  final String? studentName, studentNumber;
  factory ScanResult.fromJson(Map<String, dynamic> j) => ScanResult(
        accepted: j['status'] == 'ACCEPTED',
        status: j['status'],
        message: j['message'] ?? j['reason'] ?? '',
        studentName: j['student_name'],
        studentNumber: j['student_number'],
      );
}

class ScanLog {
  ScanLog({
    required this.id,
    required this.studentName,
    required this.tripId,
    required this.busId,
    required this.scanTime,
    required this.status,
    this.reason,
    this.syncStatus = 'SYNCED',
  });
  final int id, tripId, busId;
  final String studentName, status, syncStatus;
  final String? reason;
  final DateTime scanTime;
  factory ScanLog.fromJson(Map<String, dynamic> j) => ScanLog(
        id: _i(j['scan_id']),
        studentName: j['student_name'] ?? 'Unknown',
        tripId: _i(j['trip_id']),
        busId: _i(j['bus_id']),
        scanTime: _dt(j['scan_time']),
        status: j['status'],
        reason: j['reason'],
        syncStatus: j['sync_status'] ?? 'SYNCED',
      );
}

class ServiceAlert {
  ServiceAlert({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    this.routeId,
    required this.createdAt,
    this.isActive = true,
  });
  final int id;
  final int? routeId;
  final String title, message, severity; // INFO | WARNING | CRITICAL
  final DateTime createdAt;
  final bool isActive;
  factory ServiceAlert.fromJson(Map<String, dynamic> j) => ServiceAlert(
        id: _i(j['alert_id']),
        title: j['title'],
        message: j['message'],
        severity: j['severity'] ?? 'INFO',
        routeId: j['route_id'] == null ? null : _i(j['route_id']),
        createdAt: _dt(j['created_at']),
        isActive: j['is_active'] ?? true,
      );
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });
  final int id;
  final String title, body;
  final DateTime createdAt;
  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: _i(j['notification_id']),
        title: j['title'],
        body: j['body'],
        createdAt: _dt(j['created_at']),
      );
}

class AuditLog {
  AuditLog({
    required this.id,
    required this.userName,
    required this.action,
    required this.entityType,
    this.entityId,
    this.details,
    this.ipAddress,
    required this.createdAt,
  });
  final int id;
  final String userName, action, entityType;
  final String? entityId, details, ipAddress;
  final DateTime createdAt;
  factory AuditLog.fromJson(Map<String, dynamic> j) => AuditLog(
        id: _i(j['audit_id']),
        userName: j['user_name'] ?? 'system',
        action: j['action'],
        entityType: j['entity_type'],
        entityId: j['entity_id']?.toString(),
        details: j['details'] ??
            (j['new_values']?.toString()),
        ipAddress: j['ip_address'],
        createdAt: _dt(j['created_at']),
      );
}

class SessionRecord {
  SessionRecord({
    required this.id,
    required this.userName,
    this.ipAddress,
    this.userAgent,
    required this.createdAt,
    required this.expiresAt,
    this.revokedAt,
  });
  final int id;
  final String userName;
  final String? ipAddress, userAgent;
  final DateTime createdAt, expiresAt;
  final DateTime? revokedAt;
  bool get isActive => revokedAt == null && expiresAt.isAfter(DateTime.now());
  factory SessionRecord.fromJson(Map<String, dynamic> j) => SessionRecord(
        id: _i(j['session_id']),
        userName: j['user_name'] ?? '',
        ipAddress: j['ip_address'],
        userAgent: j['user_agent'],
        createdAt: _dt(j['created_at']),
        expiresAt: _dt(j['expires_at']),
        revokedAt: _dtn(j['revoked_at']),
      );
}

class UsageReport {
  UsageReport({
    required this.total,
    required this.accepted,
    required this.rejected,
    required this.byRoute,
  });
  final int total, accepted, rejected;
  final Map<String, int> byRoute;
  factory UsageReport.fromJson(Map<String, dynamic> j) => UsageReport(
        total: _i(j['total']),
        accepted: _i(j['accepted']),
        rejected: _i(j['rejected']),
        byRoute: ((j['by_route'] ?? {}) as Map)
            .map((k, v) => MapEntry(k.toString(), _i(v))),
      );
}
