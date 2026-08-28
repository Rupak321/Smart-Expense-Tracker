import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/models/ai_chat_message.dart';
import '../core/models/bill_reminder.dart';

class UserSettingsService {
  UserSettingsService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String? get currentUid => _auth.currentUser?.uid;

  static DocumentReference<Map<String, dynamic>> _settingsDoc() {
    final uid = currentUid;
    if (uid == null || uid.isEmpty) {
      throw StateError('User must be logged in to use Firebase storage.');
    }
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('preferences');
  }

  static CollectionReference<Map<String, dynamic>> _remindersCollection() {
    final uid = currentUid;
    if (uid == null || uid.isEmpty) {
      throw StateError('User must be logged in to use Firebase storage.');
    }
    return _firestore.collection('users').doc(uid).collection('bill_reminders');
  }

  static CollectionReference<Map<String, dynamic>> _aiSessionsCollection() {
    final uid = currentUid;
    if (uid == null || uid.isEmpty) {
      throw StateError('User must be logged in to use Firebase storage.');
    }
    return _firestore.collection('users').doc(uid).collection('ai_sessions');
  }

  static Future<ThemeMode> loadThemeMode() async {
    try {
      final snapshot = await _settingsDoc().get();
      final stored = snapshot.data()?['themeMode']?.toString();
      return _parseThemeMode(stored);
    } catch (_) {
      return ThemeMode.light;
    }
  }

  static Future<void> saveThemeMode(ThemeMode mode) async {
    try {
      await _settingsDoc().set({
        'themeMode': _themeModeToString(mode),
      }, SetOptions(merge: true));
    } catch (_) {
      // Ignore save failures for theme mode.
    }
  }

  static Future<String?> loadCurrencyCode() async {
    try {
      final snapshot = await _settingsDoc().get();
      return snapshot.data()?['currencyCode'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveCurrencyCode(String code) async {
    try {
      await _settingsDoc().set({
        'currencyCode': code,
      }, SetOptions(merge: true));
    } catch (_) {
      // Display preference only - losing it costs the user nothing but a
      // second tap next time.
    }
  }

  static Future<String?> getActiveAiSessionId() async {
    try {
      final snapshot = await _settingsDoc().get();
      return snapshot.data()?['activeAiSessionId']?.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<void> setActiveAiSessionId(String id) async {
    try {
      await _settingsDoc().set({
        'activeAiSessionId': id,
      }, SetOptions(merge: true));
    } catch (_) {
      // Ignore failures here.
    }
  }

  static Stream<List<BillReminder>> billRemindersStream() {
    try {
      return _remindersCollection()
          .orderBy('dueDate')
          .snapshots()
          .map(
            (snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              return BillReminder(
                id: doc.id,
                title: data['title']?.toString() ?? 'Bill',
                amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
                dueDate:
                    DateTime.tryParse(data['dueDate']?.toString() ?? '') ??
                    DateTime.now(),
                enabled: data['enabled'] as bool? ?? true,
                remindDaysBefore:
                    (data['remindDaysBefore'] as num?)?.toInt() ?? 1,
                notes: data['notes']?.toString() ?? '',
              );
            }).toList(),
          );
    } catch (_) {
      return const Stream.empty();
    }
  }

  static Future<List<BillReminder>> getBillRemindersOnce() async {
    try {
      final snapshot = await _remindersCollection().orderBy('dueDate').get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return BillReminder(
          id: doc.id,
          title: data['title']?.toString() ?? 'Bill',
          amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
          dueDate:
              DateTime.tryParse(data['dueDate']?.toString() ?? '') ??
              DateTime.now(),
          enabled: data['enabled'] as bool? ?? true,
          remindDaysBefore: (data['remindDaysBefore'] as num?)?.toInt() ?? 1,
          notes: data['notes']?.toString() ?? '',
        );
      }).toList();
    } catch (_) {
      return <BillReminder>[];
    }
  }

  static Future<void> saveBillReminder(BillReminder reminder) async {
    await _remindersCollection().doc(reminder.id).set(reminder.toMap());
  }

  static Future<void> deleteBillReminder(String id) async {
    await _remindersCollection().doc(id).delete();
  }

  static Stream<List<AiChatSession>> aiSessionsStream() {
    try {
      return _aiSessionsCollection()
          .orderBy('updatedAt', descending: true)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs.map((doc) {
              final raw = doc.data();
              return AiChatSession.fromMap({'id': doc.id, ...raw});
            }).toList(),
          );
    } catch (_) {
      return const Stream<List<AiChatSession>>.empty();
    }
  }

  static Stream<AiChatSession?> aiSessionStream(String id) {
    try {
      return _aiSessionsCollection().doc(id).snapshots().map((snapshot) {
        if (!snapshot.exists) {
          return null;
        }
        return AiChatSession.fromMap({'id': snapshot.id, ...snapshot.data()!});
      });
    } catch (_) {
      return Stream<AiChatSession?>.value(null);
    }
  }

  static Future<List<AiChatSession>> getAiSessionsOnce() async {
    try {
      final snapshot = await _aiSessionsCollection()
          .orderBy('updatedAt', descending: true)
          .get();
      return snapshot.docs.map((doc) {
        return AiChatSession.fromMap({'id': doc.id, ...doc.data()});
      }).toList();
    } catch (_) {
      return <AiChatSession>[];
    }
  }

  static Future<AiChatSession?> getAiSession(String id) async {
    try {
      final snapshot = await _aiSessionsCollection().doc(id).get();
      if (!snapshot.exists) {
        return null;
      }
      return AiChatSession.fromMap({'id': snapshot.id, ...snapshot.data()!});
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveAiSession(AiChatSession session) async {
    await _aiSessionsCollection().doc(session.id).set(session.toMap());
  }

  static Future<void> deleteAiSession(String id) async {
    await _aiSessionsCollection().doc(id).delete();
  }

  static ThemeMode _parseThemeMode(String? stored) {
    switch (stored) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.light;
    }
  }

  static String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
      case ThemeMode.light:
        return 'light';
    }
  }
}
