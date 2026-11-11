import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../core/config.dart';
import '../core/permissions.dart';
import '../models/models.dart';
import 'repository.dart';

/// In-memory backend that enforces the same business rules as the planned
/// API: academic-year route lookup, approval workflow, pass creation,
/// boarding verification, RBAC, lockout, audit logging.
///
/// Demo accounts (password / MFA code 123456 for privileged roles):
///   student1@wsu.ac.za  Student#123   (no application yet)
///   student2@wsu.ac.za  Student#123   (active pass, token DEMO-PASS-S2)
///   driver@wsu.ac.za    Driver#123
///   officer@wsu.ac.za   Officer#123
///   manager@wsu.ac.za   Manager#123
///   admin@wsu.ac.za     Admin#123
class MockRepository extends Repository {
  MockRepository() {
    _seed();
  }

  static const demoMfaCode = '123456';
  static const maxFailedLogins = 5;
  static const lockoutMinutes = 15;

  final _rand = Random();
  int _seq = 1000;
  int _next() => ++_seq;

  AppUser? _me;
  int? _sessionId;

  final List<AppUser> _users = [];
  final Map<int, String> _passwords = {};
  final Map<String, int> _failed = {};
  final Map<String, DateTime> _lockedUntil = {};

  final List<TransportRoute> _routes = [];
  final List<Residence> _residences = [];
  final List<Assignment> _assignments = [];
  final List<Trip> _trips = [];
  final List<Bus> _buses = [];
  final List<_App> _apps = [];
  final List<_Pass> _passes = [];
  final List<_Scan> _scans = [];
  final List<ServiceAlert> _alerts = [];
  final Map<int, List<AppNotification>> _notes = {};
  final List<AuditLog> _audit = [];
  final List<SessionRecord> _sessions = [];
  final Map<int, Set<int>> _driverTrips = {};

  void _upsert<T>(List<T> l, int i, T v) {
    if (i >= 0) {
      l[i] = v;
    } else {
      l.add(v);
    }
  }

  // ---------------------------------------------------------------- seed
  String _hash(String s) => sha256.convert(utf8.encode(s)).toString();

  void _seed() {
    final year = AppConfig.academicYear;
    for (final n in ['Southernwood', 'Town', 'Gquigney', 'Amalinda']) {
      _routes.add(TransportRoute(
        id: _routes.length + 1,
        name: n,
        description: '$n route between the residences and the main campus.',
      ));
    }
    // Sample residences (replace through the admin screens / real data).
    final res = {
      'Langham House': 'Southernwood',
      'Ikhwezi Residence': 'Southernwood',
      'Mandela Hall': 'Town',
      'Buffalo Court': 'Town',
      'Gquigney Lodge': 'Gquigney',
      'Amalinda Gardens': 'Amalinda',
      'Unassigned Annex': '',
    };
    res.forEach((name, route) {
      final r = Residence(
        id: _residences.length + 1,
        name: name,
        location: 'East London, Eastern Cape',
      );
      _residences.add(r);
      if (route.isNotEmpty) {
        _assignments.add(Assignment(
          id: _next(),
          residenceId: r.id,
          routeId: _routes.firstWhere((x) => x.name == route).id,
          academicYear: year,
          effectiveFrom: DateTime(year, 1, 1),
          effectiveTo: DateTime(year, 12, 31),
        ));
      }
    });
    // History: Langham House was on Town last year.
    _assignments.add(Assignment(
      id: _next(),
      residenceId: 1,
      routeId: 2,
      academicYear: year - 1,
      effectiveFrom: DateTime(year - 1, 1, 1),
      effectiveTo: DateTime(year - 1, 12, 31),
      isActive: false,
    ));

    const times = ['06:30', '07:15', '08:00', '12:30', '16:30', '17:15'];
    for (final r in _routes) {
      for (var i = 0; i < times.length; i++) {
        _trips.add(Trip(
          id: _next(),
          routeId: r.id,
          departure: times[i],
          direction: i < 3 ? 'INBOUND' : 'OUTBOUND',
          tripType: 'REGULAR',
        ));
      }
      _trips.add(Trip(
        id: _next(),
        routeId: r.id,
        departure: '09:00',
        direction: 'INBOUND',
        tripType: 'WEEKEND',
      ));
    }
    for (var i = 1; i <= 4; i++) {
      _buses.add(Bus(
        id: i,
        fleetNumber: 'WSU-0$i',
        registration: 'EC ${100 + i * 37} GP',
        capacity: i == 4 ? 65 : 60,
        status: i == 4 ? 'MAINTENANCE' : 'ACTIVE',
      ));
    }

    AppUser mk(String email, String first, String last, List<AppRole> roles,
        String pw,
        {String? sn}) {
      final u = AppUser(
        id: _users.length + 1,
        email: email,
        firstName: first,
        lastName: last,
        phone: '+27 71 000 00${_users.length + 10}',
        roles: roles,
        studentNumber: sn,
        fundingStatus: sn == null ? null : 'NSFAS',
      );
      _users.add(u);
      _passwords[u.id] = pw;
      return u;
    }

    final s1 = mk('student1@wsu.ac.za', 'Thandi', 'Mkhize',
        [AppRole.student], 'Student#123', sn: '220100001');
    final s2 = mk('student2@wsu.ac.za', 'Sipho', 'Dlamini',
        [AppRole.student], 'Student#123', sn: '220100002');
    final s3 = mk('student3@wsu.ac.za', 'Lerato', 'Nkosi', [AppRole.student],
        'Student#123', sn: '220100003');
    final s4 = mk('student4@wsu.ac.za', 'Aphiwe', 'Jacobs', [AppRole.student],
        'Student#123', sn: '220100004');
    final drv = mk('driver@wsu.ac.za', 'Mandla', 'Zulu', [AppRole.driver],
        'Driver#123');
    mk('officer@wsu.ac.za', 'Nomsa', 'Pillay', [AppRole.officer],
        'Officer#123');
    mk('manager@wsu.ac.za', 'Gareth', 'Botha', [AppRole.manager],
        'Manager#123');
    mk('admin@wsu.ac.za', 'Ayanda', 'Cele', [AppRole.superAdmin],
        'Admin#123');
    _notes[s1.id] = [];

    // Driver is assigned to the Southernwood and Town trips.
    _driverTrips[drv.id] = _trips
        .where((t) => t.routeId == 1 || t.routeId == 2)
        .map((t) => t.id)
        .toSet();

    // Sipho: approved, active pass on Southernwood.
    final a2 = _App(
      id: _next(),
      user: s2,
      residence: _residences[0],
      status: AppStatus.approved,
      appliedAt: DateTime.now().subtract(const Duration(days: 20)),
      reviewedAt: DateTime.now().subtract(const Duration(days: 18)),
      reviewedBy: 'Nomsa Pillay',
    );
    _apps.add(a2);
    _passes.add(_Pass(
      id: _next(),
      app: a2,
      route: _routes[0],
      year: year,
      validFrom: DateTime(year, 2, 1),
      validTo: DateTime(year, 11, 30),
      token: 'DEMO-PASS-S2',
    ));
    // Two applications waiting for review.
    for (final (u, r) in [(s3, _residences[2]), (s4, _residences[5])]) {
      _apps.add(_App(
        id: _next(),
        user: u,
        residence: r,
        status: AppStatus.underReview,
        appliedAt: DateTime.now().subtract(Duration(hours: 5 + _rand.nextInt(40))),
      ));
    }
    _alerts.add(ServiceAlert(
      id: _next(),
      title: 'Timetable change',
      message: 'Town route 16:30 departure now leaves at 16:45 on Fridays.',
      severity: 'INFO',
      routeId: 2,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ));
  }

  // ------------------------------------------------------------- helpers
  Future<void> _lag() => Future.delayed(const Duration(milliseconds: 250));

  AppUser get _user {
    final u = _me;
    if (u == null) throw ApiException('Not authenticated', code: 'UNAUTHENTICATED');
    return u;
  }

  void _authed() => _user;

  void _require(String perm) {
    if (!permissionsFor(_user.roles).contains(perm)) {
      throw ApiException('You do not have permission to do that.', code: 'FORBIDDEN');
    }
  }

  void _log(String action, String entity, Object? id, {String? details}) {
    _audit.insert(
      0,
      AuditLog(
        id: _next(),
        userName: _me?.fullName ?? 'system',
        action: action,
        entityType: entity,
        entityId: id?.toString(),
        details: details,
        ipAddress: '10.0.0.${_rand.nextInt(200) + 10}',
        createdAt: DateTime.now(),
      ),
    );
  }

  Assignment? _assignmentFor(int residenceId, int year) {
    final now = DateTime.now();
    for (final a in _assignments) {
      if (a.residenceId == residenceId &&
          a.academicYear == year &&
          a.isActive &&
          (a.effectiveFrom == null || !now.isBefore(a.effectiveFrom!)) &&
          (a.effectiveTo == null ||
              !now.isAfter(a.effectiveTo!.add(const Duration(days: 1))))) {
        return a;
      }
    }
    return null;
  }

  String _routeName(int id) => _routes.firstWhere((r) => r.id == id).name;

  Application _appDto(_App a) {
    final asg = _assignmentFor(a.residence.id, AppConfig.academicYear);
    return Application(
      id: a.id,
      studentId: a.user.id,
      studentName: a.user.fullName,
      studentNumber: a.user.studentNumber ?? '',
      residenceId: a.residence.id,
      residenceName: a.residence.name,
      routeName: asg == null ? null : _routeName(asg.routeId),
      status: a.status,
      appliedAt: a.appliedAt,
      reviewedBy: a.reviewedBy,
      reviewedAt: a.reviewedAt,
      rejectionReason: a.rejection,
    );
  }

  TransportPass _passDto(_Pass p) => TransportPass(
        id: p.id,
        studentId: p.app.user.id,
        routeId: p.route.id,
        routeName: p.route.name,
        residenceName: p.app.residence.name,
        academicYear: p.year,
        validFrom: p.validFrom,
        validTo: p.validTo,
        status: p.status,
        token: p.token,
      );

  // ---------------------------------------------------------------- auth
  @override
  Future<Session?> restoreSession() async => null;

  @override
  Future<Session> login(String email, String password, {String? mfaCode}) async {
    await _lag();
    final key = email.trim().toLowerCase();
    final lock = _lockedUntil[key];
    if (lock != null && lock.isAfter(DateTime.now())) {
      final mins = lock.difference(DateTime.now()).inMinutes + 1;
      throw ApiException(
          'Too many failed attempts. Account locked for about $mins min.',
          code: 'LOCKED');
    }
    final matches = _users.where((u) => u.email == key);
    final user = matches.isEmpty ? null : matches.first;
    if (user == null || _passwords[user.id] != password) {
      final n = (_failed[key] ?? 0) + 1;
      _failed[key] = n;
      if (n >= maxFailedLogins) {
        _lockedUntil[key] =
            DateTime.now().add(const Duration(minutes: lockoutMinutes));
        _failed[key] = 0;
        throw ApiException(
            'Too many failed attempts. Account locked for $lockoutMinutes min.',
            code: 'LOCKED');
      }
      throw ApiException(
          'Invalid email or password (${maxFailedLogins - n} attempts left).');
    }
    if (!user.isActive) throw ApiException('This account is disabled.');
    if (user.roles.any((r) => r.requiresMfa)) {
      if (mfaCode == null || mfaCode.trim().isEmpty) {
        throw MfaRequiredException();
      }
      if (mfaCode.trim() != demoMfaCode) {
        throw ApiException('Invalid verification code.');
      }
    }
    _failed[key] = 0;
    _me = user;
    final rec = SessionRecord(
      id: _next(),
      userName: user.fullName,
      ipAddress: '10.0.0.${_rand.nextInt(200) + 10}',
      userAgent: 'WSU SmartTransit App',
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 7)),
    );
    _sessions.insert(0, rec);
    _sessionId = rec.id;
    _log('LOGIN', 'session', rec.id);
    return Session(user: user, permissions: permissionsFor(user.roles));
  }

  @override
  Future<void> logout() async {
    final i = _sessions.indexWhere((s) => s.id == _sessionId);
    if (i >= 0) _revoke(i);
    _log('LOGOUT', 'session', _sessionId);
    _me = null;
    _sessionId = null;
  }

  void _revoke(int i) {
    final s = _sessions[i];
    _sessions[i] = SessionRecord(
      id: s.id,
      userName: s.userName,
      ipAddress: s.ipAddress,
      userAgent: s.userAgent,
      createdAt: s.createdAt,
      expiresAt: s.expiresAt,
      revokedAt: DateTime.now(),
    );
  }

  // ------------------------------------------------------- configuration
  @override
  Future<List<TransportRoute>> routes() async {
    await _lag();
    _authed();
    return List.of(_routes);
  }

  @override
  Future<TransportRoute> saveRoute(
      {int? id,
      required String name,
      String? description,
      required bool isActive}) async {
    await _lag();
    _require(Perm.configManage);
    if (_routes.any((r) => r.id != id && r.name.toLowerCase() == name.toLowerCase())) {
      throw ApiException('A route with that name already exists.');
    }
    final r = TransportRoute(
        id: id ?? _next(), name: name, description: description, isActive: isActive);
    final i = _routes.indexWhere((x) => x.id == id);
    _upsert(_routes, i, r);
    _log(i >= 0 ? 'ROUTE_UPDATED' : 'ROUTE_CREATED', 'route', r.id, details: name);
    return r;
  }

  @override
  Future<List<Residence>> residences() async {
    await _lag();
    _authed();
    return List.of(_residences);
  }

  @override
  Future<Residence> saveResidence(
      {int? id,
      required String name,
      String? location,
      required bool isActive}) async {
    await _lag();
    _require(Perm.configManage);
    if (_residences.any((r) => r.id != id && r.name.toLowerCase() == name.toLowerCase())) {
      throw ApiException('A residence with that name already exists.');
    }
    final r = Residence(id: id ?? _next(), name: name, location: location, isActive: isActive);
    final i = _residences.indexWhere((x) => x.id == id);
    _upsert(_residences, i, r);
    _log(i >= 0 ? 'RESIDENCE_UPDATED' : 'RESIDENCE_CREATED', 'residence', r.id, details: name);
    return r;
  }

  @override
  Future<List<Assignment>> assignments({int? year}) async {
    await _lag();
    _authed();
    return _assignments.where((a) => year == null || a.academicYear == year).toList();
  }

  @override
  Future<Assignment> saveAssignment(
      {required int residenceId, required int routeId, required int year}) async {
    await _lag();
    _require(Perm.configManage);
    final i = _assignments
        .indexWhere((a) => a.residenceId == residenceId && a.academicYear == year);
    final a = Assignment(
      id: i >= 0 ? _assignments[i].id : _next(),
      residenceId: residenceId,
      routeId: routeId,
      academicYear: year,
      effectiveFrom: DateTime(year, 1, 1),
      effectiveTo: DateTime(year, 12, 31),
    );
    final old = i >= 0 ? _routeName(_assignments[i].routeId) : null;
    _upsert(_assignments, i, a);
    _log('ASSIGNMENT_SET', 'route_residence_assignment', a.id,
        details: '${old == null ? '' : '$old -> '}${_routeName(routeId)} ($year)');
    return a;
  }

  @override
  Future<List<Trip>> trips({int? routeId}) async {
    await _lag();
    _authed();
    final l = _trips.where((t) => routeId == null || t.routeId == routeId).toList();
    l.sort((a, b) => a.departure.compareTo(b.departure));
    return l;
  }

  @override
  Future<Trip> saveTrip(
      {int? id,
      required int routeId,
      required String departure,
      required String direction,
      required String tripType,
      required bool isActive}) async {
    await _lag();
    _require(Perm.tripManage);
    final t = Trip(
        id: id ?? _next(),
        routeId: routeId,
        departure: departure,
        direction: direction,
        tripType: tripType,
        isActive: isActive);
    final i = _trips.indexWhere((x) => x.id == id);
    _upsert(_trips, i, t);
    _log(i >= 0 ? 'TRIP_UPDATED' : 'TRIP_CREATED', 'trip', t.id,
        details: '${_routeName(routeId)} $departure $direction');
    return t;
  }

  @override
  Future<List<Trip>> myDriverTrips() async {
    await _lag();
    _require(Perm.scanCreate);
    final ids = _driverTrips[_user.id] ?? {};
    final l = _trips.where((t) => ids.contains(t.id) && t.isActive).toList();
    l.sort((a, b) => a.departure.compareTo(b.departure));
    return l;
  }

  @override
  Future<List<Bus>> buses() async {
    await _lag();
    if (!permissionsFor(_user.roles).contains(Perm.busView) &&
        !permissionsFor(_user.roles).contains(Perm.scanCreate)) {
      throw ApiException('You do not have permission to do that.', code: 'FORBIDDEN');
    }
    return List.of(_buses);
  }

  @override
  Future<Bus> saveBus(
      {int? id,
      required String fleetNumber,
      required String registration,
      required int capacity,
      required String status}) async {
    await _lag();
    _require(Perm.busManage);
    final b = Bus(
        id: id ?? _next(),
        fleetNumber: fleetNumber,
        registration: registration,
        capacity: capacity,
        status: status);
    final i = _buses.indexWhere((x) => x.id == id);
    _upsert(_buses, i, b);
    _log(i >= 0 ? 'BUS_UPDATED' : 'BUS_CREATED', 'bus', b.id, details: fleetNumber);
    return b;
  }

  // --------------------------------------------------------- applications
  @override
  Future<List<Application>> applications({String? status}) async {
    await _lag();
    _require(Perm.applicationReview);
    final l = _apps.where((a) => status == null || a.status == status).toList();
    l.sort((a, b) => b.appliedAt.compareTo(a.appliedAt));
    return l.map(_appDto).toList();
  }

  @override
  Future<List<Application>> myApplications() async {
    await _lag();
    final l = _apps.where((a) => a.user.id == _user.id).toList();
    l.sort((a, b) => b.appliedAt.compareTo(a.appliedAt));
    return l.map(_appDto).toList();
  }

  @override
  Future<Application> submitApplication(int residenceId) async {
    await _lag();
    _require(Perm.applicationSubmit);
    final res = _residences.firstWhere((r) => r.id == residenceId,
        orElse: () => throw ApiException('Unknown residence.'));
    if (!res.isActive) throw ApiException('That residence is not active.');
    final year = AppConfig.academicYear;
    if (_assignmentFor(residenceId, year) == null) {
      throw ApiException(
          '${res.name} has no route assigned for $year yet. Contact the transport office.');
    }
    final open = _apps.any((a) =>
        a.user.id == _user.id &&
        (a.status == AppStatus.underReview || a.status == AppStatus.approved));
    if (open) {
      throw ApiException('You already have an active application or pass.');
    }
    // SUBMITTED -> validated -> UNDER_REVIEW
    final a = _App(
        id: _next(),
        user: _user,
        residence: res,
        status: AppStatus.underReview,
        appliedAt: DateTime.now());
    _apps.add(a);
    _log('APPLICATION_SUBMITTED', 'application', a.id, details: res.name);
    return _appDto(a);
  }

  _App _find(int id) => _apps.firstWhere((a) => a.id == id,
      orElse: () => throw ApiException('Application not found.'));

  @override
  Future<Application> approveApplication(int id) async {
    await _lag();
    _require(Perm.applicationReview);
    final a = _find(id);
    if (a.status != AppStatus.underReview) {
      throw ApiException('Only applications under review can be approved.');
    }
    final year = AppConfig.academicYear;
    final asg = _assignmentFor(a.residence.id, year);
    if (asg == null) {
      throw ApiException('Residence has no route for $year. Assign one first.');
    }
    a.status = AppStatus.approved;
    a.reviewedBy = _user.fullName;
    a.reviewedAt = DateTime.now();
    final route = _routes.firstWhere((r) => r.id == asg.routeId);
    final token = List.generate(
        24, (_) => 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[_rand.nextInt(32)]).join();
    _passes.add(_Pass(
      id: _next(),
      app: a,
      route: route,
      year: year,
      validFrom: DateTime(year, 2, 1),
      validTo: DateTime(year, 11, 30),
      token: token,
    ));
    _notes.putIfAbsent(a.user.id, () => []).insert(
        0,
        AppNotification(
            id: _next(),
            title: 'Transport application approved',
            body:
                'Your pass for the ${route.name} route is now active. Open the Pass tab to show your QR code.',
            createdAt: DateTime.now()));
    _log('APPLICATION_APPROVED', 'application', a.id,
        details: '${a.user.fullName} -> ${route.name}');
    return _appDto(a);
  }

  @override
  Future<Application> rejectApplication(int id, String reason) async {
    await _lag();
    _require(Perm.applicationReview);
    if (reason.trim().isEmpty) throw ApiException('A rejection reason is required.');
    final a = _find(id);
    if (a.status != AppStatus.underReview) {
      throw ApiException('Only applications under review can be rejected.');
    }
    a.status = AppStatus.rejected;
    a.rejection = reason.trim();
    a.reviewedBy = _user.fullName;
    a.reviewedAt = DateTime.now();
    _notes.putIfAbsent(a.user.id, () => []).insert(
        0,
        AppNotification(
            id: _next(),
            title: 'Transport application rejected',
            body: 'Reason: ${a.rejection}',
            createdAt: DateTime.now()));
    _log('APPLICATION_REJECTED', 'application', a.id, details: a.rejection);
    return _appDto(a);
  }

  @override
  Future<TransportPass?> myPass() async {
    await _lag();
    final l = _passes.where((p) => p.app.user.id == _user.id).toList();
    return l.isEmpty ? null : _passDto(l.last);
  }

  // ------------------------------------------------------------- scanning
  @override
  Future<ScanResult> submitScan(ScanRequest r) async {
    if (simulateOffline) throw NetworkException();
    await _lag();
    _require(Perm.scanCreate);
    if (_scans.any((s) => s.clientId == r.clientId)) {
      return ScanResult(accepted: true, status: 'ACCEPTED', message: 'Already synced');
    }
    final token = r.token.startsWith('WSUST:') ? r.token.substring(6) : r.token;
    final hash = _hash(token);
    _Pass? pass;
    for (final p in _passes) {
      if (p.hash == hash) pass = p;
    }
    String status = 'ACCEPTED';
    String message = 'Boarding approved';
    final trip = _trips.firstWhere((t) => t.id == r.tripId);

    if (!(_driverTrips[_user.id] ?? {}).contains(trip.id)) {
      status = 'REJECTED';
      message = 'You are not assigned to this trip.';
    } else if (pass == null) {
      status = 'REJECTED';
      message = 'Pass not recognised.';
    } else if (pass.status != 'ACTIVE') {
      status = 'REJECTED';
      message = 'Pass is ${pass.status.toLowerCase()}.';
    } else if (r.scannedAt.isBefore(pass.validFrom) ||
        r.scannedAt.isAfter(pass.validTo.add(const Duration(days: 1)))) {
      status = 'REJECTED';
      message = 'Pass is outside its validity period.';
    } else if (pass.route.id != trip.routeId) {
      status = 'REJECTED';
      message = 'Pass is for the ${pass.route.name} route, not this trip.';
    } else if (_scans.any((s) =>
        s.pass == pass &&
        s.tripId == trip.id &&
        s.status == 'ACCEPTED' &&
        s.time.day == r.scannedAt.day &&
        s.time.month == r.scannedAt.month)) {
      status = 'DUPLICATE';
      message = 'Already scanned on this trip today.';
    }
    _scans.insert(
        0,
        _Scan(
            id: _next(),
            clientId: r.clientId,
            pass: pass,
            driver: _user,
            tripId: trip.id,
            busId: r.busId,
            time: r.scannedAt,
            status: status,
            reason: status == 'ACCEPTED' ? null : message));
    return ScanResult(
      accepted: status == 'ACCEPTED',
      status: status,
      message: message,
      studentName: pass?.app.user.fullName,
      studentNumber: pass?.app.user.studentNumber,
    );
  }

  @override
  Future<List<ScanLog>> scanLogs({bool mine = false}) async {
    await _lag();
    final src = mine ? _scans.where((s) => s.driver.id == _user.id) : _scans;
    return src
        .map((s) => ScanLog(
              id: s.id,
              studentName: s.pass?.app.user.fullName ?? 'Unknown pass',
              tripId: s.tripId,
              busId: s.busId,
              scanTime: s.time,
              status: s.status,
              reason: s.reason,
            ))
        .toList();
  }

  // -------------------------------------------------------- communication
  @override
  Future<List<ServiceAlert>> alerts() async {
    await _lag();
    _authed();
    return _alerts.where((a) => a.isActive).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<ServiceAlert> createAlert(
      {required String title,
      required String message,
      required String severity,
      int? routeId}) async {
    await _lag();
    _require(Perm.alertManage);
    final a = ServiceAlert(
        id: _next(),
        title: title,
        message: message,
        severity: severity,
        routeId: routeId,
        createdAt: DateTime.now());
    _alerts.add(a);
    _log('ALERT_CREATED', 'service_alert', a.id, details: title);
    return a;
  }

  @override
  Future<void> deactivateAlert(int id) async {
    await _lag();
    _require(Perm.alertManage);
    final i = _alerts.indexWhere((a) => a.id == id);
    if (i < 0) return;
    final a = _alerts[i];
    _alerts[i] = ServiceAlert(
        id: a.id,
        title: a.title,
        message: a.message,
        severity: a.severity,
        routeId: a.routeId,
        createdAt: a.createdAt,
        isActive: false);
    _log('ALERT_CLOSED', 'service_alert', id);
  }

  @override
  Future<List<AppNotification>> notifications() async {
    await _lag();
    return List.of(_notes[_user.id] ?? []);
  }

  // ------------------------------------------------- reporting & admin
  @override
  Future<UsageReport> usageReport() async {
    await _lag();
    _require(Perm.reportView);
    final byRoute = <String, int>{for (final r in _routes) r.name: 0};
    for (final s in _scans.where((s) => s.status == 'ACCEPTED')) {
      final t = _trips.firstWhere((t) => t.id == s.tripId);
      final n = _routeName(t.routeId);
      byRoute[n] = (byRoute[n] ?? 0) + 1;
    }
    final acc = _scans.where((s) => s.status == 'ACCEPTED').length;
    return UsageReport(
        total: _scans.length,
        accepted: acc,
        rejected: _scans.length - acc,
        byRoute: byRoute);
  }

  @override
  Future<List<AppUser>> users() async {
    await _lag();
    _require(Perm.userManage);
    return List.of(_users);
  }

  @override
  Future<AppUser> updateUser(int id, {String? status, List<AppRole>? roles}) async {
    await _lag();
    _require(Perm.userManage);
    final u = _users.firstWhere((u) => u.id == id);
    if (id == _user.id && (status == 'DISABLED' || (roles != null && !roles.contains(AppRole.superAdmin)))) {
      throw ApiException('You cannot remove your own admin access.');
    }
    if (roles != null && roles.isEmpty) {
      throw ApiException('A user needs at least one role.');
    }
    if (status != null) {
      u.status = status;
      _log('USER_STATUS_CHANGED', 'user', id, details: '${u.email} -> $status');
      if (status != 'ACTIVE') {
        for (var i = 0; i < _sessions.length; i++) {
          if (_sessions[i].userName == u.fullName && _sessions[i].isActive) _revoke(i);
        }
      }
    }
    if (roles != null) {
      u.roles = roles;
      _log('USER_ROLES_CHANGED', 'user', id,
          details: '${u.email}: ${roles.map((r) => r.code).join(', ')}');
    }
    return u;
  }

  @override
  Future<List<AuditLog>> auditLogs() async {
    await _lag();
    final p = permissionsFor(_user.roles);
    if (p.contains(Perm.auditView)) return List.of(_audit);
    if (p.contains(Perm.auditViewLimited)) {
      // Officers only see application / pass activity.
      return _audit.where((a) => a.entityType == 'application' || a.entityType == 'pass').toList();
    }
    throw ApiException('You do not have permission to do that.', code: 'FORBIDDEN');
  }

  @override
  Future<List<SessionRecord>> sessions() async {
    await _lag();
    _require(Perm.sessionManage);
    return List.of(_sessions);
  }

  @override
  Future<void> revokeSession(int id) async {
    await _lag();
    _require(Perm.sessionManage);
    final i = _sessions.indexWhere((s) => s.id == id);
    if (i >= 0) {
      _revoke(i);
      _log('SESSION_REVOKED', 'session', id);
    }
  }
}

class _App {
  _App({
    required this.id,
    required this.user,
    required this.residence,
    required this.status,
    required this.appliedAt,
    this.reviewedBy,
    this.reviewedAt,
  });
  final int id;
  final AppUser user;
  final Residence residence;
  String status;
  final DateTime appliedAt;
  String? reviewedBy, rejection;
  DateTime? reviewedAt;
}

class _Pass {
  _Pass({
    required this.id,
    required this.app,
    required this.route,
    required this.year,
    required this.validFrom,
    required this.validTo,
    required this.token,
  }) : hash = sha256.convert(utf8.encode(token)).toString();
  final int id, year;
  final _App app;
  final TransportRoute route;
  final DateTime validFrom, validTo;
  final String token;
  final String hash;
  String status = 'ACTIVE';
}

class _Scan {
  _Scan({
    required this.id,
    required this.clientId,
    required this.pass,
    required this.driver,
    required this.tripId,
    required this.busId,
    required this.time,
    required this.status,
    this.reason,
  });
  final int id, tripId, busId;
  final String clientId, status;
  final String? reason;
  final _Pass? pass;
  final AppUser driver;
  final DateTime time;
}
