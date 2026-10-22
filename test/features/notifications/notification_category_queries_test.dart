import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:prism_engine/core/database/database_helper.dart';
import 'package:prism_engine/core/database/queries/notification_category_queries.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
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
              is_priority INTEGER DEFAULT 0,
              category_labels TEXT NOT NULL DEFAULT '[]',
              classification_scores TEXT NOT NULL DEFAULT '{}',
              classification_version TEXT,
              classification_confidence REAL
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
    'counts multi-label and unclassified notifications by category',
    () async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('notifications', {
        'source_key': 'bill-payment',
        'package_name': 'example',
        'timestamp': 100,
        'category': 'Banking & Payments',
        'category_labels': '["Banking & Payments","Bills & Due Dates"]',
      });
      await db.insert('notifications', {
        'source_key': 'placement',
        'package_name': 'example',
        'timestamp': 200,
        'category': 'Placement & Jobs',
        'category_labels': '["Placement & Jobs"]',
      });
      await db.insert('notifications', {
        'source_key': 'unclassified',
        'package_name': 'example',
        'timestamp': 300,
        'category': 'Unclassified',
        'category_labels': '[]',
      });
      await db.insert('notifications', {
        'source_key': 'legacy-bank',
        'package_name': 'example',
        'timestamp': 400,
        'category': 'Bank',
        'category_labels': '[]',
      });

      final counts = await NotificationCategoryQueries.getCategoryCounts([
        'Placement & Jobs',
        'Banking & Payments',
        'Bills & Due Dates',
        'Unclassified',
      ]);

      expect(counts['Placement & Jobs'], 1);
      expect(counts['Banking & Payments'], 2);
      expect(counts['Bills & Due Dates'], 1);
      expect(counts['Unclassified'], 1);
    },
  );

  test(
    'category detail includes matching labels and legacy bank rows',
    () async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('notifications', {
        'source_key': 'multi-label-bill',
        'package_name': 'example',
        'timestamp': 100,
        'category': 'Banking & Payments',
        'category_labels': '["Banking & Payments","Bills & Due Dates"]',
      });
      await db.insert('notifications', {
        'source_key': 'legacy-bank',
        'package_name': 'example',
        'timestamp': 200,
        'category': 'Bank',
        'category_labels': '[]',
      });

      final banking =
          await NotificationCategoryQueries.getNotificationsForCategory(
            'Banking & Payments',
          );
      final bills =
          await NotificationCategoryQueries.getNotificationsForCategory(
            'Bills & Due Dates',
          );

      expect(banking.map((row) => row['source_key']), [
        'legacy-bank',
        'multi-label-bill',
      ]);
      expect(bills.map((row) => row['source_key']), ['multi-label-bill']);
    },
  );
}
