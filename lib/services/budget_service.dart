import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../core/models/budget.dart';

class BudgetService {
  BudgetService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static CollectionReference<Map<String, dynamic>> _collection() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('User must be logged in to use Firebase storage.');
    }
    return _firestore.collection('users').doc(uid).collection('budgets');
  }

  static Stream<List<Budget>> stream() {
    try {
      return _collection().snapshots().map(
        (snapshot) => snapshot.docs
            .map((doc) => Budget.fromMap(doc.id, doc.data()))
            .toList(),
      );
    } catch (_) {
      return Stream.value(const <Budget>[]);
    }
  }

  static Future<List<Budget>> getOnce() async {
    try {
      final snapshot = await _collection().get();
      return snapshot.docs
          .map((doc) => Budget.fromMap(doc.id, doc.data()))
          .toList();
    } catch (_) {
      return <Budget>[];
    }
  }

  /// Creates or replaces the budget for [category].
  ///
  /// One ceiling per category, so setting a second one for the same category
  /// overwrites the first rather than leaving two competing limits in place.
  static Future<void> save({
    required String? category,
    required int limitPaisa,
  }) async {
    final existing = await getOnce();
    final match = existing
        .where((budget) => budget.category == category)
        .firstOrNull;

    final id = match?.id ?? const Uuid().v4();
    final budget = Budget(
      id: id,
      category: category,
      limitPaisa: limitPaisa,
      createdAt: match?.createdAt ?? DateTime.now(),
    );

    await _collection().doc(id).set(budget.toMap());
  }

  static Future<void> delete(String id) async {
    await _collection().doc(id).delete();
  }
}
