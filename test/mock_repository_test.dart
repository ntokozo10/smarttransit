import 'package:flutter_test/flutter_test.dart';
import 'package:wsu_smarttransit/core/config.dart';
import 'package:wsu_smarttransit/data/mock_repository.dart';
import 'package:wsu_smarttransit/data/repository.dart';
import 'package:wsu_smarttransit/models/models.dart';

Future<void> asStudent(MockRepository r, [String e = 'student1@wsu.ac.za']) =>
    r.login(e, 'Student#123');
Future<void> asOfficer(MockRepository r) =>
    r.login('officer@wsu.ac.za', 'Officer#123', mfaCode: '123456');

void main() {
  final year = AppConfig.academicYear;

  test('application -> approval -> pass -> boarding scan', () async {
    final r = MockRepository();
    await asStudent(r);

    // Residence with no route for this year cannot apply (id 7).
    expect(() => r.submitApplication(7), throwsA(isA<ApiException>()));

    final app = await r.submitApplication(3); // Mandela Hall -> Town
    expect(app.status, AppStatus.underReview);
    expect(app.routeName, 'Town');
    expect(() => r.submitApplication(3), throwsA(isA<ApiException>()));
    expect(await r.myPass(), isNull);

    // Students cannot approve.
    expect(() => r.approveApplication(app.id),
        throwsA(predicate((e) => e is ApiException && e.code == 'FORBIDDEN')));

    await asOfficer(r);
    final approved = await r.approveApplication(app.id);
    expect(approved.status, AppStatus.approved);

    await asStudent(r);
    final pass = (await r.myPass())!;
    expect(pass.routeName, 'Town');
    expect((await r.notifications()).first.title, contains('approved'));

    await r.login('driver@wsu.ac.za', 'Driver#123');
    final trips = await r.myDriverTrips();
    final town = trips.firstWhere((t) => t.routeId == 2);
    final other = trips.firstWhere((t) => t.routeId == 1);
    final when = DateTime(year, 6, 15, 7, 15);
    ScanRequest req(String tok, Trip t, String id) => ScanRequest(
        token: tok, tripId: t.id, busId: 1, scannedAt: when, clientId: id);

    expect((await r.submitScan(req(pass.qrPayload, town, 'a'))).accepted, isTrue);
    expect((await r.submitScan(req(pass.qrPayload, town, 'b'))).status, 'DUPLICATE');
    final wrong = await r.submitScan(req(pass.qrPayload, other, 'c'));
    expect(wrong.accepted, isFalse);
    expect(wrong.message, contains('Town'));
    expect((await r.submitScan(req('nonsense', town, 'd'))).accepted, isFalse);
    // Same client id is idempotent (offline sync retry).
    expect((await r.submitScan(req(pass.qrPayload, town, 'a'))).accepted, isTrue);
  });

  test('rejection requires a reason', () async {
    final r = MockRepository();
    await asOfficer(r);
    final pending = await r.applications(status: AppStatus.underReview);
    expect(() => r.rejectApplication(pending.first.id, ' '), throwsA(isA<ApiException>()));
    final rej = await r.rejectApplication(pending.first.id, 'Not enrolled');
    expect(rej.status, AppStatus.rejected);
  });

  test('privileged roles need MFA', () async {
    final r = MockRepository();
    expect(() => r.login('manager@wsu.ac.za', 'Manager#123'),
        throwsA(isA<MfaRequiredException>()));
    expect(() => r.login('manager@wsu.ac.za', 'Manager#123', mfaCode: '000000'),
        throwsA(isA<ApiException>()));
    final s = await r.login('manager@wsu.ac.za', 'Manager#123', mfaCode: '123456');
    expect(s.primaryRole, AppRole.manager);
  });

  test('lockout after repeated failures', () async {
    final r = MockRepository();
    for (var i = 0; i < 4; i++) {
      await expectLater(r.login('student1@wsu.ac.za', 'bad'), throwsA(isA<ApiException>()));
    }
    await expectLater(r.login('student1@wsu.ac.za', 'bad'),
        throwsA(predicate((e) => e is ApiException && e.code == 'LOCKED')));
    await expectLater(r.login('student1@wsu.ac.za', 'Student#123'),
        throwsA(predicate((e) => e is ApiException && e.code == 'LOCKED')));
  });

  test('academic-year assignments preserve history', () async {
    final r = MockRepository();
    await r.login('manager@wsu.ac.za', 'Manager#123', mfaCode: '123456');
    final before = await r.assignments(year: year - 1);
    expect(before.where((a) => a.residenceId == 1 && a.routeId == 2), isNotEmpty);
    await r.saveAssignment(residenceId: 1, routeId: 4, year: year);
    final last = await r.assignments(year: year - 1);
    expect(last.where((a) => a.residenceId == 1).single.routeId, 2);
    final now = await r.assignments(year: year);
    expect(now.where((a) => a.residenceId == 1).single.routeId, 4);
  });

  test('officer sees only limited audit log; student cannot see any', () async {
    final r = MockRepository();
    await asOfficer(r);
    final p = (await r.applications(status: AppStatus.underReview)).first;
    await r.approveApplication(p.id);
    final logs = await r.auditLogs();
    expect(logs.every((l) => l.entityType == 'application' || l.entityType == 'pass'), isTrue);
    await asStudent(r);
    expect(() => r.auditLogs(), throwsA(isA<ApiException>()));
    expect(() => r.users(), throwsA(isA<ApiException>()));
  });
}
