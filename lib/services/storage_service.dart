import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/app_usage_summary_record.dart';
import '../models/location_record.dart';
import '../models/move_event_record.dart';
import '../models/usage_event_record.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'trackos.db');
    return openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE locations (
            id       INTEGER PRIMARY KEY AUTOINCREMENT,
            lat      REAL    NOT NULL,
            lng      REAL    NOT NULL,
            accuracy REAL    NOT NULL,
            altitude REAL    NOT NULL,
            speed    REAL    NOT NULL,
            timestamp INTEGER NOT NULL,
            synced   INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await _createUsageSummariesTable(db);
        await _createUsageEventsTable(db);
        await _createMoveEventsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createUsageSummariesTable(db);
        }
        if (oldVersion < 3) {
          await _createUsageEventsTable(db);
        }
        if (oldVersion >= 2 && oldVersion < 4) {
          await db.execute(
            'ALTER TABLE usage_summaries ADD COLUMN cumulative_foreground_time_ms INTEGER',
          );
        }
        if (oldVersion < 5) {
          await _createMoveEventsTable(db);
        }
      },
    );
  }

  Future<void> _createUsageSummariesTable(Database db) async {
    await db.execute('''
      CREATE TABLE usage_summaries (
        id                 INTEGER PRIMARY KEY AUTOINCREMENT,
        package_name       TEXT    NOT NULL,
        app_name           TEXT    NOT NULL,
        window_start_ms    INTEGER NOT NULL,
        window_end_ms      INTEGER NOT NULL,
        foreground_time_ms INTEGER NOT NULL,
        cumulative_foreground_time_ms INTEGER,
        last_used_ms       INTEGER,
        synced             INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_usage_summaries_sync_window ON usage_summaries(synced, window_end_ms)',
    );
    await db.execute(
      'CREATE INDEX idx_usage_summaries_package_window ON usage_summaries(package_name, window_end_ms)',
    );
  }

  Future<void> _createMoveEventsTable(Database db) async {
    await db.execute('''
      CREATE TABLE move_events (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        record_key     TEXT    NOT NULL,
        move_type      TEXT    NOT NULL,
        confidence     REAL,
        occurred_at_ms INTEGER NOT NULL,
        synced         INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_move_events_record_key ON move_events(record_key)',
    );
    await db.execute(
      'CREATE INDEX idx_move_events_sync_time ON move_events(synced, occurred_at_ms)',
    );
    await db.execute(
      'CREATE INDEX idx_move_events_type_time ON move_events(move_type, occurred_at_ms)',
    );
  }

  Future<void> _createUsageEventsTable(Database db) async {
    await db.execute('''
      CREATE TABLE usage_events (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        record_key     TEXT    NOT NULL,
        event_type     TEXT    NOT NULL,
        package_name   TEXT,
        class_name     TEXT,
        occurred_at_ms INTEGER NOT NULL,
        source         TEXT    NOT NULL,
        metadata       TEXT,
        synced         INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_usage_events_record_key ON usage_events(record_key)',
    );
    await db.execute(
      'CREATE INDEX idx_usage_events_sync_time ON usage_events(synced, occurred_at_ms)',
    );
    await db.execute(
      'CREATE INDEX idx_usage_events_type_time ON usage_events(event_type, occurred_at_ms)',
    );
    await db.execute(
      'CREATE INDEX idx_usage_events_package_time ON usage_events(package_name, occurred_at_ms)',
    );
  }

  Future<int> insert(LocationRecord record) async {
    final database = await db;
    return database.insert('locations', record.toMap());
  }

  Future<List<LocationRecord>> queryAll({int limit = 100, int offset = 0}) async {
    final database = await db;
    final maps = await database.query(
      'locations',
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map(LocationRecord.fromMap).toList();
  }

  Future<List<LocationRecord>> queryUnsynced({int limit = 50}) async {
    final database = await db;
    final maps = await database.query(
      'locations',
      where: 'synced = 0',
      orderBy: 'timestamp ASC',
      limit: limit,
    );
    return maps.map(LocationRecord.fromMap).toList();
  }

  Future<void> markSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final database = await db;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await database.rawUpdate(
      'UPDATE locations SET synced = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  Future<int> count() async {
    final database = await db;
    final result = await database.rawQuery('SELECT COUNT(*) as c FROM locations');
    return (result.first['c'] as int?) ?? 0;
  }

  Future<void> insertUsageSummaries(List<AppUsageSummaryRecord> records) async {
    if (records.isEmpty) return;

    final database = await db;
    final normalizedRecords = await _normalizeUsageSummaries(records);
    final batch = database.batch();
    for (final record in normalizedRecords) {
      batch.insert('usage_summaries', record.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<List<AppUsageSummaryRecord>> _normalizeUsageSummaries(
    List<AppUsageSummaryRecord> records,
  ) async {
    final sortedRecords = [...records]..sort((left, right) => left.windowEndMs.compareTo(right.windowEndMs));
    final latestSnapshotByPackage = <String, AppUsageSummaryRecord?>{};
    final normalizedRecords = <AppUsageSummaryRecord>[];

    for (final record in sortedRecords) {
      latestSnapshotByPackage[record.packageName] ??=
          await latestUsageSummaryByPackage(record.packageName);
      final previous = latestSnapshotByPackage[record.packageName];
      final windowDurationMs = (record.windowEndMs - record.windowStartMs).clamp(0, 24 * 60 * 60 * 1000);
      final rawCumulativeMs = record.cumulativeForegroundTimeMs ?? record.foregroundTimeMs;

      var deltaMs = rawCumulativeMs;
      if (previous?.cumulativeForegroundTimeMs != null &&
          _isSameLocalDay(previous!.windowEndMs, record.windowEndMs) &&
          rawCumulativeMs >= previous.cumulativeForegroundTimeMs!) {
        deltaMs = rawCumulativeMs - previous.cumulativeForegroundTimeMs!;
      }

      deltaMs = deltaMs.clamp(0, windowDurationMs);

      final normalized = record.copyWith(
        foregroundTimeMs: deltaMs,
        cumulativeForegroundTimeMs: rawCumulativeMs,
      );
      normalizedRecords.add(normalized);
      latestSnapshotByPackage[record.packageName] = normalized;
    }

    return normalizedRecords;
  }

  bool _isSameLocalDay(int leftMs, int rightMs) {
    final left = DateTime.fromMillisecondsSinceEpoch(leftMs);
    final right = DateTime.fromMillisecondsSinceEpoch(rightMs);
    return left.year == right.year && left.month == right.month && left.day == right.day;
  }

  Future<List<AppUsageSummaryRecord>> queryUnsyncedUsageSummaries({int limit = 100}) async {
    final database = await db;
    final maps = await database.query(
      'usage_summaries',
      where: 'synced = 0',
      orderBy: 'window_end_ms ASC',
      limit: limit,
    );
    return maps.map(AppUsageSummaryRecord.fromMap).toList();
  }

  Future<void> markUsageSummariesSynced(List<int> ids) async {
    if (ids.isEmpty) return;

    final database = await db;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await database.rawUpdate(
      'UPDATE usage_summaries SET synced = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  Future<int> countUsageSummaries() async {
    final database = await db;
    final result = await database.rawQuery('SELECT COUNT(*) as c FROM usage_summaries');
    return (result.first['c'] as int?) ?? 0;
  }

  Future<AppUsageSummaryRecord?> latestUsageSummary() async {
    final database = await db;
    final maps = await database.query(
      'usage_summaries',
      orderBy: 'window_end_ms DESC',
      limit: 1,
    );
    if (maps.isEmpty) {
      return null;
    }

    return AppUsageSummaryRecord.fromMap(maps.first);
  }

  Future<AppUsageSummaryRecord?> latestUsageSummaryByPackage(String packageName) async {
    final database = await db;
    final maps = await database.query(
      'usage_summaries',
      where: 'package_name = ?',
      whereArgs: [packageName],
      orderBy: 'window_end_ms DESC',
      limit: 1,
    );
    if (maps.isEmpty) {
      return null;
    }

    return AppUsageSummaryRecord.fromMap(maps.first);
  }

  Future<void> insertUsageEvents(List<UsageEventRecord> records) async {
    if (records.isEmpty) return;

    final database = await db;
    final batch = database.batch();
    for (final record in records) {
      batch.insert(
        'usage_events',
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<UsageEventRecord>> queryUnsyncedUsageEvents({int limit = 200}) async {
    final database = await db;
    final maps = await database.query(
      'usage_events',
      where: 'synced = 0',
      orderBy: 'occurred_at_ms ASC',
      limit: limit,
    );
    return maps.map(UsageEventRecord.fromMap).toList();
  }

  Future<void> markUsageEventsSynced(List<int> ids) async {
    if (ids.isEmpty) return;

    final database = await db;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await database.rawUpdate(
      'UPDATE usage_events SET synced = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  Future<int> countUsageEvents() async {
    final database = await db;
    final result = await database.rawQuery('SELECT COUNT(*) as c FROM usage_events');
    return (result.first['c'] as int?) ?? 0;
  }

  Future<UsageEventRecord?> latestUsageEvent() async {
    final database = await db;
    final maps = await database.query(
      'usage_events',
      orderBy: 'occurred_at_ms DESC',
      limit: 1,
    );
    if (maps.isEmpty) {
      return null;
    }

    return UsageEventRecord.fromMap(maps.first);
  }

  Future<void> insertMoveEvents(List<MoveEventRecord> records) async {
    if (records.isEmpty) return;

    final database = await db;
    final batch = database.batch();
    for (final record in records) {
      batch.insert(
        'move_events',
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<MoveEventRecord>> queryUnsyncedMoveEvents({int limit = 200}) async {
    final database = await db;
    final maps = await database.query(
      'move_events',
      where: 'synced = 0',
      orderBy: 'occurred_at_ms ASC',
      limit: limit,
    );
    return maps.map(MoveEventRecord.fromMap).toList();
  }

  Future<void> markMoveEventsSynced(List<int> ids) async {
    if (ids.isEmpty) return;

    final database = await db;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await database.rawUpdate(
      'UPDATE move_events SET synced = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  Future<int> countMoveEvents() async {
    final database = await db;
    final result = await database.rawQuery('SELECT COUNT(*) as c FROM move_events');
    return (result.first['c'] as int?) ?? 0;
  }

  Future<void> clearAll() async {
    final database = await db;
    await database.delete('locations');
    await database.delete('usage_summaries');
    await database.delete('usage_events');
    await database.delete('move_events');
  }
}
