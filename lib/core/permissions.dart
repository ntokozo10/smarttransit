import '../models/models.dart';

/// Permission codes (role_permissions table). The server is authoritative;
/// this client mirror only decides what UI to show (design doc section 8).
class Perm {
  static const applicationSubmit = 'application.submit';
  static const applicationReview = 'application.review';
  static const configView = 'config.view';
  static const configManage = 'config.manage';
  static const tripManage = 'trip.manage';
  static const busView = 'bus.view';
  static const busManage = 'bus.manage';
  static const alertManage = 'alert.manage';
  static const reportView = 'report.view';
  static const auditViewLimited = 'audit.view_limited';
  static const auditView = 'audit.view';
  static const userManage = 'user.manage';
  static const sessionManage = 'session.manage';
  static const scanCreate = 'scan.create';
}

const _officer = {
  Perm.applicationReview,
  Perm.configView,
  Perm.busView,
  Perm.alertManage,
  Perm.auditViewLimited,
};
const _manager = {
  ..._officer,
  Perm.configManage,
  Perm.tripManage,
  Perm.busManage,
  Perm.reportView,
};

final Map<AppRole, Set<String>> rolePermissions = {
  AppRole.student: {Perm.applicationSubmit},
  AppRole.driver: {Perm.scanCreate},
  AppRole.officer: _officer,
  AppRole.manager: _manager,
  AppRole.superAdmin: {
    ..._manager,
    Perm.auditView,
    Perm.userManage,
    Perm.sessionManage,
  },
};

Set<String> permissionsFor(Iterable<AppRole> roles) =>
    roles.expand((r) => rolePermissions[r] ?? const <String>{}).toSet();
