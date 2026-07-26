import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/models/expense_model.dart';
import '../core/models/user_profile_model.dart';

class UserDataService {
  UserDataService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<void> initialize() async {
    await Future<void>.value();
  }

  static String? get currentUid => _auth.currentUser?.uid;

  static Future<void> saveAuthUserProfileIfMissing() async {
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }

    final snapshot = await _profileDoc().get();
    if (snapshot.exists) {
      return;
    }

    await _profileDoc().set({
      'name': user.displayName ?? '',
      'phoneNumber': '',
      'address': '',
      'email': user.email ?? '',
      'occupation': '',
      'updatedAt': Timestamp.fromDate(DateTime.now()),
      'profileImagePath': user.photoURL,
    });
  }

  static CollectionReference<Map<String, dynamic>> _userCollection() {
    final uid = currentUid;
    if (uid == null || uid.isEmpty) {
      throw StateError('User must be logged in to use Firebase storage.');
    }
    return _firestore.collection('users').doc(uid).collection('data');
  }

  static CollectionReference<ExpenseModel> _transactionCollection() {
    return _userCollection().withConverter<ExpenseModel>(
      fromFirestore: (snapshot, _) => _expenseFromSnapshot(snapshot),
      toFirestore: (expense, _) => {
        'title': expense.title,
        'amount': expense.amount,
        'category': expense.category,
        'date': Timestamp.fromDate(expense.date),
        'isExpense': expense.isExpense,
      },
    );
  }

  static ExpenseModel _expenseFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final title = data['title']?.toString() ?? '';
    final category = data['category']?.toString() ?? 'Other';
    final storedIsExpense = data['isExpense'] as bool? ?? true;
    final normalizedIsExpense = _looksLikeIncome(title, category)
        ? false
        : storedIsExpense;

    return ExpenseModel(
      id: snapshot.id,
      title: title,
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      category: category,
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isExpense: normalizedIsExpense,
    );
  }

  static bool _looksLikeIncome(String title, String category) {
    final text = '$title $category'.toLowerCase();
    final outgoingPatterns = [
      RegExp(r'\b(gave|give|sent|send|paid|pay|transferred|transfer)\s+(to\s+)?(mom|mother|dad|father|parent|parents|family|friend|brother|sister)\b'),
      RegExp(r'\b(to|for)\s+(mom|mother|dad|father|parent|parents|family|friend|brother|sister)\b'),
    ];
    if (outgoingPatterns.any((pattern) => pattern.hasMatch(text))) {
      return false;
    }

    final incomingPatterns = [
      RegExp(r'\b(mom|mother|dad|father|parent|parents|family|friend|brother|sister)\s+(gave|sent|paid|transferred|send)\b'),
      RegExp(r'\b(cash|money|payment|transfer)\s+from\s+(mom|mother|dad|father|parent|parents|family|friend|brother|sister)\b'),
      RegExp(r'\b(got|received|recieved)\s+.*\bfrom\s+\w+'),
      RegExp(r'\b(gave|sent|paid|transferred)\s+me\b'),
    ];
    if (incomingPatterns.any((pattern) => pattern.hasMatch(text))) {
      return true;
    }

    const incomeSignals = [
      'income',
      'salary',
      'office salary',
      'paycheck',
      'earned',
      'received',
      'credited',
      'freelance',
      'business',
      'bonus',
      'commission',
      'investment',
      'dividend',
      'gift',
      'refund',
      'reimbursement',
      'allowance',
      'pocket money',
      'cash from',
    ];
    return incomeSignals.any(text.contains);
  }

  static DocumentReference<Map<String, dynamic>> _profileDoc() {
    final uid = currentUid;
    if (uid == null || uid.isEmpty) {
      throw StateError('User must be logged in to use Firebase storage.');
    }
    return _firestore.collection('users').doc(uid);
  }

  static Stream<List<ExpenseModel>> transactionsStream() {
    try {
      return _transactionCollection().snapshots().map((snapshot) {
        _repairMisclassifiedIncome(snapshot.docs);
        return snapshot.docs.map((doc) => doc.data()).toList();
      });
    } catch (_) {
      return Stream.value(const <ExpenseModel>[]);
    }
  }

  static void _repairMisclassifiedIncome(
    List<QueryDocumentSnapshot<ExpenseModel>> docs,
  ) {
    for (final doc in docs) {
      final transaction = doc.data();
      if (!transaction.isExpense ||
          !_looksLikeIncome(transaction.title, transaction.category)) {
        continue;
      }

      doc.reference.set(transaction);
    }
  }

  static Future<List<ExpenseModel>> getTransactionsOnce() async {
    try {
      final snapshot = await _transactionCollection().get();
      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (_) {
      return <ExpenseModel>[];
    }
  }

  static Future<List<ExpenseModel>> getRecentTransactions(int limit) async {
    try {
      final snapshot = await _transactionCollection()
          .orderBy('date', descending: true)
          .limit(limit)
          .get();
      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (_) {
      return <ExpenseModel>[];
    }
  }

  static Future<ExpenseModel?> getTransactionById(String id) async {
    try {
      final snapshot = await _transactionCollection().doc(id).get();
      if (!snapshot.exists) {
        return null;
      }
      return snapshot.data();
    } catch (_) {
      return null;
    }
  }

  static Future<void> updateTransaction(
    String id,
    ExpenseModel transaction,
  ) async {
    try {
      await _transactionCollection().doc(id).set(transaction);
    } catch (e) {
      throw Exception('Unable to update transaction in Firebase: $e');
    }
  }

  static Future<UserProfileModel?> getProfileOnce() async {
    try {
      final snapshot = await _profileDoc().get();
      if (!snapshot.exists || snapshot.data() == null) {
        final user = _auth.currentUser;
        if (user == null) {
          return null;
        }
        return UserProfileModel(
          name: user.displayName ?? '',
          phoneNumber: '',
          address: '',
          email: user.email ?? '',
          occupation: '',
          updatedAt: DateTime.now(),
          profileImagePath: user.photoURL,
        );
      }

      final data = snapshot.data()!;
      return UserProfileModel(
        name: data['name']?.toString() ?? '',
        phoneNumber: data['phoneNumber']?.toString() ?? '',
        address: data['address']?.toString() ?? '',
        email: data['email']?.toString() ?? '',
        occupation: data['occupation']?.toString() ?? '',
        updatedAt:
            (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        profileImagePath: data['profileImagePath']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> addTransaction(ExpenseModel transaction) async {
    try {
      await _transactionCollection().add(transaction);
    } catch (e) {
      throw Exception('Unable to save transaction to Firebase: $e');
    }
  }

  static Future<void> deleteTransaction(String id) async {
    try {
      await _transactionCollection().doc(id).delete();
    } catch (e) {
      throw Exception('Unable to delete transaction from Firebase: $e');
    }
  }

  static Stream<UserProfileModel?> profileStream() {
    try {
      return _profileDoc().snapshots().map((snapshot) {
        if (!snapshot.exists) {
          final user = _auth.currentUser;
          if (user != null) {
            return UserProfileModel(
              name: user.displayName ?? '',
              phoneNumber: '',
              address: '',
              email: user.email ?? '',
              occupation: '',
              updatedAt: DateTime.now(),
              profileImagePath: user.photoURL,
            );
          }
          return null;
        }

        final data = snapshot.data();
        if (data == null) {
          final user = _auth.currentUser;
          if (user != null) {
            return UserProfileModel(
              name: user.displayName ?? '',
              phoneNumber: '',
              address: '',
              email: user.email ?? '',
              occupation: '',
              updatedAt: DateTime.now(),
              profileImagePath: user.photoURL,
            );
          }
          return null;
        }

        return UserProfileModel(
          name: data['name']?.toString() ?? '',
          phoneNumber: data['phoneNumber']?.toString() ?? '',
          address: data['address']?.toString() ?? '',
          email: data['email']?.toString() ?? '',
          occupation: data['occupation']?.toString() ?? '',
          updatedAt:
              (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          profileImagePath: data['profileImagePath']?.toString(),
        );
      });
    } catch (_) {
      return Stream.value(null);
    }
  }

  static Future<void> saveProfile(UserProfileModel profile) async {
    try {
      await _profileDoc().set({
        'name': profile.name,
        'phoneNumber': profile.phoneNumber,
        'address': profile.address,
        'email': profile.email,
        'occupation': profile.occupation,
        'updatedAt': Timestamp.fromDate(profile.updatedAt),
        'profileImagePath': profile.profileImagePath,
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Unable to save profile to Firebase: $e');
    }
  }
}
