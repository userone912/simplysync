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
  static const int _databaseVersion = 2;

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
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Create sync_records table with optimized indexes
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
        deleted INTEGER NOT NULL DEFAULT 0,
        syncSessionId TEXT
      )
    ''');

    // Create indexes for frequently queried columns
    await db.execute('''
      CREATE INDEX idx_sync_records_file_path ON $syncRecordsTable (filePath)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_sync_records_status ON $syncRecordsTable (status)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_sync_records_synced_at ON $syncRecordsTable (syncedAt DESC)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_sync_records_session_id ON $syncRecordsTable (syncSessionId)
    ''');

    // Create synced_folders table with indexes
    await db.execute('''
      CREATE TABLE $syncedFoldersTable (
        id TEXT PRIMARY KEY,
        localPath TEXT NOT NULL,
        name TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        autoDelete INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Create index for enabled folders query
    await db.execute('''
      CREATE INDEX idx_synced_folders_enabled ON $syncedFoldersTable (enabled)
    ''');
    
    Logger.info('📊 Database created with optimized indexes');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add syncSessionId column to sync_records table
      await db.execute('ALTER TABLE $syncRecordsTable ADD COLUMN syncSessionId TEXT');
    }
  }

  // SyncRecord operations
  static Future<int> insertSyncRecord(SyncRecord record) async {
    final db = await database;
    return await db.insert(syncRecordsTable, record.toMap());
  }

  static Future<List<SyncRecord>> getAllSyncRecords() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      syncRecordsTable,
      orderBy: 'syncedAt DESC, lastModified DESC',
    );
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

  static Future<List<SyncRecord>> getRecentSyncRecords(Duration duration) async {
    final db = await database;
    final cutoffTime = DateTime.now().subtract(duration).millisecondsSinceEpoch;
    
    final List<Map<String, dynamic>> maps = await db.query(
      syncRecordsTable,
      where: 'syncedAt >= ?',
      whereArgs: [cutoffTime],
      orderBy: 'syncedAt DESC',
    );
    
    return List.generate(maps.length, (i) => SyncRecord.fromMap(maps[i]));
  }

  static Future<List<SyncRecord>> getSyncRecordsBySession(String syncSessionId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      syncRecordsTable,
      where: 'syncSessionId = ? AND syncedAt IS NOT NULL',
      whereArgs: [syncSessionId],
      orderBy: 'syncedAt DESC',
    );
    return List.generate(maps.length, (i) => SyncRecord.fromMap(maps[i]));
  }

  static Future<String?> getLatestSyncSessionId() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      syncRecordsTable,
      where: 'syncSessionId IS NOT NULL AND syncedAt IS NOT NULL',
      orderBy: 'syncedAt DESC',
      limit: 1,
    );
    
    if (maps.isNotEmpty) {
      return maps.first['syncSessionId'] as String?;
    }
    return null;
  }

  static Future<List<SyncRecord>> getLatestSyncSessionRecords({int limit = 50}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      syncRecordsTable,
      orderBy: 'syncedAt DESC',
      limit: limit,
      where: 'syncedAt IS NOT NULL',
    );
    return List.generate(maps.length, (i) => SyncRecord.fromMap(maps[i]));
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

  /// Batch insert sync records for better performance
  static Future<void> insertSyncRecordsBatch(List<SyncRecord> records) async {
    final db = await database;
    final batch = db.batch();
    
    for (final record in records) {
      batch.insert(syncRecordsTable, record.toMap());
    }
    
    await batch.commit(noResult: true);
    Logger.info('📊 Batch inserted ${records.length} sync records');
  }

  /// Clean up old sync records to maintain performance
  static Future<int> cleanupOldSyncRecords({int keepDays = 30}) async {
    final db = await database;
    final cutoffTime = DateTime.now().subtract(Duration(days: keepDays)).millisecondsSinceEpoch;
    
    final deletedCount = await db.delete(
      syncRecordsTable,
      where: 'syncedAt IS NOT NULL AND syncedAt < ? AND status = ?',
      whereArgs: [cutoffTime, SyncStatus.completed.name],
    );
    
    if (deletedCount > 0) {
      Logger.info('🧹 Cleaned up $deletedCount old sync records');
      // Vacuum database to reclaim space
      await db.execute('VACUUM');
    }
    
    return deletedCount;
  }

  /// Get sync statistics for dashboard
  static Future<Map<String, dynamic>> getSyncStatistics() async {
    final db = await database;
    
    // Get counts by status
    final List<Map<String, dynamic>> statusCounts = await db.rawQuery('''
      SELECT status, COUNT(*) as count 
      FROM $syncRecordsTable 
      GROUP BY status
    ''');
    
    // Get total size of synced files
    final List<Map<String, dynamic>> sizeResult = await db.rawQuery('''
      SELECT SUM(fileSize) as totalSize 
      FROM $syncRecordsTable 
      WHERE status = ?
    ''', [SyncStatus.completed.name]);
    
    // Get recent activity count (last 7 days)
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final List<Map<String, dynamic>> recentActivity = await db.rawQuery('''
      SELECT COUNT(*) as recentCount 
      FROM $syncRecordsTable 
      WHERE syncedAt > ?
    ''', [sevenDaysAgo]);
    
    final stats = <String, dynamic>{
      'statusCounts': {for (var row in statusCounts) row['status']: row['count']},
      'totalSyncedSize': sizeResult.first['totalSize'] ?? 0,
      'recentActivityCount': recentActivity.first['recentCount'] ?? 0,
    };
    
    return stats;
  }

  /// Get sync progress for a given session
  static Future<Map<String, int>> getSyncProgressBySession(String syncSessionId) async {
    final db = await database;
    // Total files in this session
    final totalResult = await db.rawQuery('''
      SELECT COUNT(*) as total FROM $syncRecordsTable WHERE syncSessionId = ?
    ''', [syncSessionId]);
    final total = totalResult.first['total'] as int? ?? 0;

    // Completed files
    final completedResult = await db.rawQuery('''
      SELECT COUNT(*) as completed FROM $syncRecordsTable WHERE syncSessionId = ? AND status = ?
    ''', [syncSessionId, SyncStatus.completed.name]);
    final completed = completedResult.first['completed'] as int? ?? 0;

    // In-progress files
    final inProgressResult = await db.rawQuery('''
      SELECT COUNT(*) as inProgress FROM $syncRecordsTable WHERE syncSessionId = ? AND status = ?
    ''', [syncSessionId, SyncStatus.syncing.name]);
    final inProgress = inProgressResult.first['inProgress'] as int? ?? 0;

    // Failed files
    final failedResult = await db.rawQuery('''
      SELECT COUNT(*) as failed FROM $syncRecordsTable WHERE syncSessionId = ? AND status = ?
    ''', [syncSessionId, SyncStatus.failed.name]);
    final failed = failedResult.first['failed'] as int? ?? 0;

    return {
      'total': total,
      'completed': completed,
      'inProgress': inProgress,
      'failed': failed,
    };
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
