import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:prism_engine/core/database/database_helper.dart';
import 'package:prism_engine/features/notifications/services/dedup_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  test('DedupService detects duplicate within 10 minutes and enriches merchant', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE notifications (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              source_key TEXT UNIQUE,
              package_name TEXT NOT NULL,
              sender_header TEXT,
              title TEXT,
              text TEXT,
              timestamp INTEGER NOT NULL,
              category TEXT NOT NULL,
              merchant TEXT,
              amount REAL,
              txn_type TEXT,
              is_priority INTEGER DEFAULT 0
            )
          ''');
        },
      ),
    );

    DatabaseHelper.instance.setDatabaseForTesting(db);

    final baseTime = DateTime(2026, 9, 19, 14, 0).millisecondsSinceEpoch;

    // 1. Initial event: Bank SMS arrives without merchant name
    await DatabaseHelper.instance.insertNotification({
      'source_key': 'sms_001',
      'package_name': 'com.android.mms',
      'sender_header': 'HDFCBK',
      'title': 'Debit Alert',
      'text': 'Rs 350.00 debited from a/c 1234',
      'timestamp': baseTime,
      'category': 'Bank',
      'merchant': null,
      'amount': 350.0,
      'txn_type': 'DEBIT',
      'is_priority': 0,
    });

    // 2. Multi-channel duplicate: GPay notification arrives 2 minutes later with merchant 'Zomato'
    final isDup = await DedupService.isDuplicateAndReconcile(
      amount: 350.0,
      type: 'DEBIT',
      timestamp: baseTime + (2 * 60 * 1000), // 2 minutes later
      merchant: 'Zomato',
    );

    expect(isDup, isTrue, reason: 'Identical amount & type within 2 minutes must be recognized as duplicate');

    // Verify existing record is enriched with the merchant name
    final records = await DatabaseHelper.instance.queryNotifications();
    expect(records.length, equals(1));
    expect(records.first['merchant'], equals('Zomato'));

    // 3. Fresh transaction: Same amount but 20 minutes later (outside sliding window)
    final isOutsideWindowDup = await DedupService.isDuplicateAndReconcile(
      amount: 350.0,
      type: 'DEBIT',
      timestamp: baseTime + (20 * 60 * 1000), // 20 minutes later
      merchant: 'Swiggy',
    );

    expect(isOutsideWindowDup, isFalse, reason: 'Event 20 minutes later is outside sliding window');
  });
}
