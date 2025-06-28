import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/sync_record.dart';
import '../models/synced_folder.dart';
import '../utils/logger.dart';

class DatabaseService {
  static Database? _database;
  static const String _databaseName = 'simplysync.db';
  static const int _databaseVersion = 1;

  // Table names
  static const String syncRecordsTable = 'sync_records';
  static const String syncedFoldersTable = 'synced_folders';

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _databaseName);
    
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Create sync_records table
    await db.execute('''
      CREATE TABLE $syncRecordsTable (
        id TEXT PRIMARY KEY,
        filePath TEXT NOT NULL,
        fileName TEXT NOT NULL,
        fileSize INTEGER NOT NULL,
        hash TEXT NOT NULL,
        lastModified INTEGER NOT NULL,
        syncedAt INTEGER,
        status TEXT NOT NULL,
        errorMessage TEXT,
        deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Create synced_folders table
    await db.execute('''
      CREATE TABLE $syncedFoldersTable (
        id TEXT PRIMARY KEY,
        localPath TEXT NOT NULL,
        name TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        autoDelete INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Create indexes
    await db.execute('''
      CREATE INDEX idx_sync_records_filepath ON $syncRecordsTable(filePath)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_sync_records_status ON $syncRecordsTable(status)
    ''');
  }

  // SyncRecord operations
  static Future<int> insertSyncRecord(SyncRecord record) async {
    final db = await database;
    return await db.insert(syncRecordsTable, record.toMap());
  }

  static Future<List<SyncRecord>> getAllSyncRecords() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(syncRecordsTable);
    return List.generate(maps.length, (i) => SyncRecord.fromMap(maps[i]));
  }

  static Future<List<SyncRecord>> getSyncRecordsByStatus(SyncStatus status) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      syncRecordsTable,
      where: 'status = ?',
      whereArgs: [status.name],
    );
    return List.generate(maps.length, (i) => SyncRecord.fromMap(maps[i]));
  }

  static Future<SyncRecord?> getSyncRecordByPath(String filePath) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      syncRecordsTable,
      where: 'filePath = ?',
      whereArgs: [filePath],
      limit: 1,
    );
    
    if (maps.isNotEmpty) {
      return SyncRecord.fromMap(maps.first);
    }
    return null;
  }

  static Future<int> updateSyncRecord(SyncRecord record) async {
    final db = await database;
    return await db.update(
      syncRecordsTable,
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  static Future<int> deleteSyncRecord(String id) async {
    final db = await database;
    return await db.delete(
      syncRecordsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // SyncedFolder operations
  static Future<int> insertSyncedFolder(SyncedFolder folder) async {
    final db = await database;
    final result = await db.insert(syncedFoldersTable, folder.toMap());
    Logger.info('DatabaseService: Inserted synced folder ${folder.name} with id ${folder.id}');
    return result;
  }

  static Future<List<SyncedFolder>> getAllSyncedFolders() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(syncedFoldersTable);
    final folders = List.generate(maps.length, (i) => SyncedFolder.fromMap(maps[i]));
    Logger.info('DatabaseService: Retrieved ${folders.length} synced folders');
    for (final folder in folders) {
      Logger.debug('  - ${folder.name}: ${folder.localPath} (enabled: ${folder.enabled})');
    }
    return folders;
  }

  static Future<List<SyncedFolder>> getEnabledSyncedFolders() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      syncedFoldersTable,
      where: 'enabled = ?',
      whereArgs: [1],
    );
    return List.generate(maps.length, (i) => SyncedFolder.fromMap(maps[i]));
  }

  static Future<int> updateSyncedFolder(SyncedFolder folder) async {
    final db = await database;
    return await db.update(
      syncedFoldersTable,
      folder.toMap(),
      where: 'id = ?',
      whereArgs: [folder.id],
    );
  }

  static Future<int> deleteSyncedFolder(String id) async {
    final db = await database;
    return await db.delete(
      syncedFoldersTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Utility functions
  static Future<void> clearAllData() async {
    final db = await database;
    await db.delete(syncRecordsTable);
    await db.delete(syncedFoldersTable);
  }

  static Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
