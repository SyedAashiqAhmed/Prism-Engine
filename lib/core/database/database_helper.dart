import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Centralized SQLite database manager for Prism Engine.
/// Handles schema creation, migration, indexes, and test hooks.
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  /// Allows injection of in-memory or mock database for deterministic unit testing.
  void setDatabaseForTesting(Database? db) {
    _database = db;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('prism_engine.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Transactions & Notifications Ledger Table
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

    // 2. Performance-Critical Composite Indexes
    await db.execute('''
      CREATE INDEX idx_txn_category_time 
      ON notifications (category, timestamp DESC)
    ''');

    await db.execute('''
      CREATE INDEX idx_txn_amount_time 
      ON notifications (amount, timestamp)
    ''');

    await db.execute('''
      CREATE INDEX idx_txn_source_key 
      ON notifications (source_key)
    ''');
  }

  Future<int> insertNotification(Map<String, dynamic> row) async {
    final db = await database;
    return await db.insert(
      'notifications',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> queryNotifications({
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    final db = await database;
    return await db.query(
      'notifications',
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
    );
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
