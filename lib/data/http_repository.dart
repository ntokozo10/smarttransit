import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'repository.dart';

/// REST client for the Node/Express API described in the Phase 1 design.
/// Tokens are held in the platform keystore (flutter_secure_storage).
/// See README for the endpoint contract.
class HttpRepository extends Repository {
  HttpRepository(this.baseUrl, {http.Client? client, FlutterSecureStorage? storage})
      : _http = client ?? http.Client(),
        _store = storage ?? const FlutterSecureStorage();

  final String baseUrl;
  final http.Client _http;
  final FlutterSecureStorage _store;
  String? _access;
  String? _refresh;

  // ------------------------------------------------------------ plumbing
  Uri _uri(String path, [Map<String, String?>? q]) {
    final params = <String, String>{
      for (final e in (q ?? {}).entries)
        if (e.value != null) e.key: e.value!,
    };
    return Uri.parse('$baseUrl$path').replace(queryParameters: params.isEmpty ? null : params);
  }

  Future<dynamic> _send(String method, String path,
      {Map<String, String?>? query, Object? body, bool auth = true, bool retry = true}) async {
    final req = http.Request(method, _uri(path, query));
    req.headers['Content-Type'] = 'application/json';
    req.headers['Accept'] = 'application/json';
    if (auth && _access != null) req.headers['Authorization'] = 'Bearer $_access';
    if (body != null) req.body = jsonEncode(body);
    http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 20)));
    } on SocketException {
      throw NetworkException();
    } on TimeoutException {
      throw NetworkException('The server took too long to respond');
    } on http.ClientException {
      throw NetworkException();
    }
    if (res.statusCode == 401 && auth && retry && _refresh != null) {
      if (await _tryRefresh()) {
        return _send(method, path, query: query, body: body, auth: auth, retry: false);
      }
    }
    final decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;
    final err = decoded is Map ? (decoded['error'] ?? decoded) : null;
    final code = err is Map ? err['code']?.toString() : null;
    final msg = err is Map ? (err['message']?.toString() ?? 'Request failed') : 'Request failed (${res.statusCode})';
    if (code == 'MFA_REQUIRED') throw MfaRequiredException();
    throw ApiException(msg, code: code);
  }

  Future<bool> _tryRefresh() async {
    try {
      final r = await _send('POST', '/auth/refresh',
          body: {'refresh_token': _refresh}, auth: false, retry: false);
      await _saveTokens(r['access_token'], r['refresh_token'] ?? _refresh);
      return true;
    } catch (_) {
      await _clearTokens();
      return false;
    }
  }

  Future<void> _saveTokens(String access, String? refresh) async {
    _access = access;
    _refresh = refresh;
    await _store.write(key: 'access', value: access);
    if (refresh != null) await _store.write(key: 'refresh', value: refresh);
  }

  Future<void> _clearTokens() async {
    _access = _refresh = null;
    await _store.delete(key: 'access');
    await _store.delete(key: 'refresh');
  }

  Future<List<T>> _list<T>(String path, T Function(Map<String, dynamic>) f,
      {Map<String, String?>? query}) async {
    final r = await _send('GET', path, query: query);
    final data = r is Map ? (r['data'] ?? r['items'] ?? []) : r;
    return (data as List).map((e) => f(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<T> _obj<T>(String method, String path, T Function(Map<String, dynamic>) f,
      {Object? body}) async {
    final r = await _send(method, path, body: body);
    final data = (r is Map && r['data'] is Map) ? r['data'] : r;
    return f(Map<String, dynamic>.from(data as Map));
  }

  Session _session(Map<String, dynamic> j) => Session(
        user: AppUser.fromJson(Map<String, dynamic>.from(j['user'])),
        permissions: ((j['permissions'] ?? []) as List).map((e) => e.toString()).toSet(),
      );

  // ---------------------------------------------------------------- auth
  @override
  Future<Session?> restoreSession() async {
    _access = await _store.read(key: 'access');
    _refresh = await _store.read(key: 'refresh');
    if (_access == null) return null;
    try {
      final r = await _send('GET', '/auth/me');
      return _session(Map<String, dynamic>.from(r is Map && r['data'] is Map ? r['data'] : r));
    } on NetworkException {
      rethrow;
    } catch (_) {
      await _clearTokens();
      return null;
    }
  }

  @override
  Future<Session> login(String email, String password, {String? mfaCode}) async {
    final r = await _send('POST', '/auth/login',
        auth: false,
        body: {
          'email': email.trim(),
          'password': password,
          if (mfaCode != null && mfaCode.isNotEmpty) 'mfa_code': mfaCode,
        });
    await _saveTokens(r['access_token'], r['refresh_token']);
    return _session(Map<String, dynamic>.from(r));
  }

  @override
  Future<void> logout() async {
    try {
      await _send('POST', '/auth/logout', body: {'refresh_token': _refresh});
    } catch (_) {
      // Always clear local credentials, even if the server is unreachable.
    }
    await _clearTokens();
  }

  // ------------------------------------------------------- configuration
  @override
  Future<List<TransportRoute>> routes() => _list('/routes', TransportRoute.fromJson);

  @override
  Future<TransportRoute> saveRoute(
          {int? id, required String name, String? description, required bool isActive}) =>
      _obj(id == null ? 'POST' : 'PATCH', id == null ? '/routes' : '/routes/$id',
          TransportRoute.fromJson,
          body: {'route_name': name, 'description': description, 'is_active': isActive});

  @override
  Future<List<Residence>> residences() => _list('/residences', Residence.fromJson);

  @override
  Future<Residence> saveResidence(
          {int? id, required String name, String? location, required bool isActive}) =>
      _obj(id == null ? 'POST' : 'PATCH', id == null ? '/residences' : '/residences/$id',
          Residence.fromJson,
          body: {'residence_name': name, 'location': location, 'is_active': isActive});

  @override
  Future<List<Assignment>> assignments({int? year}) => _list(
      '/route-residence-assignments', Assignment.fromJson,
      query: {'academic_year': year?.toString()});

  @override
  Future<Assignment> saveAssignment(
          {required int residenceId, required int routeId, required int year}) =>
      _obj('POST', '/route-residence-assignments', Assignment.fromJson,
          body: {'residence_id': residenceId, 'route_id': routeId, 'academic_year': year});

  @override
  Future<List<Trip>> trips({int? routeId}) =>
      _list('/trips', Trip.fromJson, query: {'route_id': routeId?.toString()});

  @override
  Future<Trip> saveTrip(
          {int? id,
          required int routeId,
          required String departure,
          required String direction,
          required String tripType,
          required bool isActive}) =>
      _obj(id == null ? 'POST' : 'PATCH', id == null ? '/trips' : '/trips/$id', Trip.fromJson,
          body: {
            'route_id': routeId,
            'departure_time': departure,
            'direction': direction,
            'trip_type': tripType,
            'is_active': isActive,
          });

  @override
  Future<List<Trip>> myDriverTrips() => _list('/drivers/me/trips', Trip.fromJson);

  @override
  Future<List<Bus>> buses() => _list('/buses', Bus.fromJson);

  @override
  Future<Bus> saveBus(
          {int? id,
          required String fleetNumber,
          required String registration,
          required int capacity,
          required String status}) =>
      _obj(id == null ? 'POST' : 'PATCH', id == null ? '/buses' : '/buses/$id', Bus.fromJson,
          body: {
            'fleet_number': fleetNumber,
            'registration_number': registration,
            'capacity': capacity,
            'status': status,
          });

  // --------------------------------------------------------- applications
  @override
  Future<List<Application>> applications({String? status}) =>
      _list('/applications', Application.fromJson, query: {'status': status});

  @override
  Future<List<Application>> myApplications() =>
      _list('/applications', Application.fromJson, query: {'mine': 'true'});

  @override
  Future<Application> submitApplication(int residenceId) =>
      _obj('POST', '/applications', Application.fromJson, body: {'residence_id': residenceId});

  @override
  Future<Application> approveApplication(int id) =>
      _obj('PATCH', '/applications/$id/approve', Application.fromJson);

  @override
  Future<Application> rejectApplication(int id, String reason) =>
      _obj('PATCH', '/applications/$id/reject', Application.fromJson,
          body: {'rejection_reason': reason});

  @override
  Future<TransportPass?> myPass() async {
    try {
      return await _obj('GET', '/passes/me', TransportPass.fromJson);
    } on ApiException catch (e) {
      if (e.code == 'NOT_FOUND') return null;
      rethrow;
    }
  }

  // ------------------------------------------------------------- scanning
  @override
  Future<ScanResult> submitScan(ScanRequest request) =>
      _obj('POST', '/scans', ScanResult.fromJson, body: request.toJson());

  @override
  Future<List<ScanLog>> scanLogs({bool mine = false}) =>
      _list('/scans', ScanLog.fromJson, query: {'mine': mine ? 'true' : null});

  // -------------------------------------------------------- communication
  @override
  Future<List<ServiceAlert>> alerts() => _list('/service-alerts', ServiceAlert.fromJson);

  @override
  Future<ServiceAlert> createAlert(
          {required String title,
          required String message,
          required String severity,
          int? routeId}) =>
      _obj('POST', '/service-alerts', ServiceAlert.fromJson, body: {
        'title': title,
        'message': message,
        'severity': severity,
        'route_id': routeId,
      });

  @override
  Future<void> deactivateAlert(int id) async {
    await _send('PATCH', '/service-alerts/$id', body: {'is_active': false});
  }

  @override
  Future<List<AppNotification>> notifications() =>
      _list('/notifications', AppNotification.fromJson);

  // ------------------------------------------------- reporting & admin
  @override
  Future<UsageReport> usageReport() => _obj('GET', '/reports/usage', UsageReport.fromJson);

  @override
  Future<List<AppUser>> users() => _list('/users', AppUser.fromJson);

  @override
  Future<AppUser> updateUser(int id, {String? status, List<AppRole>? roles}) =>
      _obj('PATCH', '/users/$id', AppUser.fromJson, body: {
        if (status != null) 'status': status,
        if (roles != null) 'roles': roles.map((r) => r.code).toList(),
      });

  @override
  Future<List<AuditLog>> auditLogs() => _list('/audit-logs', AuditLog.fromJson);

  @override
  Future<List<SessionRecord>> sessions() => _list('/sessions', SessionRecord.fromJson);

  @override
  Future<void> revokeSession(int id) async {
    await _send('DELETE', '/sessions/$id');
  }
}
