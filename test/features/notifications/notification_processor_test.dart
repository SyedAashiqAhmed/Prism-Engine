import 'package:flutter_notification_listener/flutter_notification_listener.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:prism_engine/core/database/database_helper.dart';
import 'package:prism_engine/features/notifications/services/notification_processor.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
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
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
  });

  test(
    'persists a credit using the notification timestamp and transaction type',
    () async {
      final timestamp = DateTime(2026, 10, 20, 9).millisecondsSinceEpoch;
      final event = NotificationEvent(
        packageName: 'com.example.bank',
        title: 'Credit alert',
        text: 'Rs 2,500.00 has been credited to your account',
        timestamp: timestamp,
        uniqueId: 'credit-event',
      );

      expect(await NotificationProcessor.process(event), isTrue);
      final rows = await DatabaseHelper.instance.queryNotifications();

      expect(rows, hasLength(1));
      expect(rows.single['amount'], 2500.0);
      expect(rows.single['txn_type'], 'CREDIT');
      expect(rows.single['timestamp'], timestamp);
      expect(rows.single['package_name'], 'com.example.bank');
    },
  );

  test('persists a debit and ignores non-financial notifications', () async {
    final event = NotificationEvent(
      packageName: 'com.example.wallet',
      title: 'Payment alert',
      text: 'Paid Rs 85.00 to Chai Point',
      timestamp: DateTime(2026, 10, 20, 10).millisecondsSinceEpoch,
      uniqueId: 'debit-event',
    );

    expect(await NotificationProcessor.process(event), isTrue);
    expect(
      await NotificationProcessor.process(
        NotificationEvent(
          packageName: 'com.example.wallet',
          title: 'Message',
          text: 'Your order is ready',
        ),
      ),
      isFalse,
    );

    final rows = await DatabaseHelper.instance.queryNotifications();
    expect(rows, hasLength(1));
    expect(rows.single['amount'], 85.0);
    expect(rows.single['txn_type'], 'DEBIT');
  });

  test(
    'concurrent notifications for one transaction are stored only once',
    () async {
      final timestamp = DateTime(2026, 10, 20, 11).millisecondsSinceEpoch;
      final events = [
        NotificationEvent(
          packageName: 'com.example.bank',
          title: 'Debit alert',
          text: 'Rs 500.00 debited from your account',
          timestamp: timestamp,
          uniqueId: 'bank-event',
        ),
        NotificationEvent(
          packageName: 'com.example.wallet',
          title: 'Payment successful',
          text: 'Paid Rs 500.00 to Merchant',
          timestamp: timestamp + 60 * 1000,
          uniqueId: 'wallet-event',
        ),
      ];

      await Future.wait(events.map(NotificationProcessor.process));

      final rows = await DatabaseHelper.instance.queryNotifications();
      expect(rows, hasLength(1));
    },
  );
}
