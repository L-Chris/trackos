import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/location_record.dart';

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
      version: 1,
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
      },
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

  Future<void> clearAll() async {
    final database = await db;
    await database.delete('locations');
  }
}
