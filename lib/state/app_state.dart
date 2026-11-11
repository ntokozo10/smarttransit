import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repository.dart';
import '../models/models.dart';

/// Session + driver offline queue. Screens read data straight from [repo].
class AppState extends ChangeNotifier {
  AppState(this.repo);
  final Repository repo;

  Session? session;
  bool booting = true;

  // ---- driver offline queue (design doc: offline mode + sync queue)
  static const _queueKey = 'pending_scans_v1';
  final List<ScanRequest> pending = [];
  bool syncing = false;

  Future<void> boot() async {
    try {
      session = await repo.restoreSession();
    } catch (_) {
      session = null;
    }
    await _loadQueue();
    booting = false;
    notifyListeners();
  }

  Future<void> login(String email, String password, {String? mfaCode}) async {
    session = await repo.login(email, password, mfaCode: mfaCode);
    notifyListeners();
  }

  Future<void> logout() async {
    await repo.logout();
    session = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------- queue
  Future<void> _loadQueue() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_queueKey);
      if (raw != null) {
        pending
          ..clear()
          ..addAll((jsonDecode(raw) as List)
              .map((e) => ScanRequest.fromJson(Map<String, dynamic>.from(e))));
      }
    } catch (_) {}
  }

  Future<void> _saveQueue() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_queueKey, jsonEncode(pending.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  /// Submit a scan; if the server is unreachable the scan is queued and null
  /// is returned so the UI can show "saved offline".
  Future<ScanResult?> scan(ScanRequest r) async {
    try {
      return await repo.submitScan(r);
    } on NetworkException {
      pending.add(r);
      await _saveQueue();
      notifyListeners();
      return null;
    }
  }

  /// Flush the queue. Returns how many were synced.
  Future<int> syncPending() async {
    if (syncing || pending.isEmpty) return 0;
    syncing = true;
    notifyListeners();
    var done = 0;
    try {
      for (final r in List.of(pending)) {
        try {
          await repo.submitScan(r); // server de-duplicates on client_id
          pending.remove(r);
          done++;
        } on NetworkException {
          break;
        } on ApiException {
          pending.remove(r); // rejected by server rules; drop from queue
          done++;
        }
      }
    } finally {
      syncing = false;
      await _saveQueue();
      notifyListeners();
    }
    return done;
  }
}
