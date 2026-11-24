import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

/// 本地 SQLite 数据库。所有数据只存在用户设备上。
class AppDb {
  static Database? _db;

  static Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'footprints.db'),
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE settings(
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE sessions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            startedAt INTEGER NOT NULL,
            endedAt INTEGER,
            distance REAL NOT NULL DEFAULT 0,
            duration INTEGER NOT NULL DEFAULT 0,
            maxSpeed REAL NOT NULL DEFAULT 0,
            avgSpeed REAL NOT NULL DEFAULT 0,
            pointCount INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE points(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sessionId INTEGER NOT NULL,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            ts INTEGER NOT NULL,
            speed REAL NOT NULL DEFAULT 0,
            altitude REAL NOT NULL DEFAULT 0,
            FOREIGN KEY(sessionId) REFERENCES sessions(id) ON DELETE CASCADE
          )''');
        await db.execute('CREATE INDEX idx_points_session ON points(sessionId)');
      },
    );
    return _db!;
  }

  /// 通用设置项读取（键值对）
  static Future<String?> getSetting(String key) async {
    final db = await _open();
    final rows = await db.query('settings', where: 'key=?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  /// 通用设置项写入
  static Future<void> setSetting(String key, String value) async {
    final db = await _open();
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 「自动生成账号」：首次启动在本地生成一个 UUID 作为数据主键。
  /// 该 ID 只存在于设备数据库中，没有任何服务器交互。
  static Future<String> localId() async {
    final db = await _open();
    final rows = await db.query('settings', where: 'key=?', whereArgs: ['local_id']);
    if (rows.isNotEmpty) return rows.first['value'] as String;
    final id = const Uuid().v4();
    await db.insert('settings', {'key': 'local_id', 'value': id});
    return id;
  }

  static Future<List<Session>> sessions() async {
    final db = await _open();
    final rows = await db.query('sessions', orderBy: 'startedAt DESC');
    return rows.map(Session.fromMap).toList();
  }

  static Future<List<TrackPoint>> points(int sessionId) async {
    final db = await _open();
    final rows = await db
        .query('points', where: 'sessionId=?', whereArgs: [sessionId], orderBy: 'ts ASC');
    return rows.map(TrackPoint.fromMap).toList();
  }

  static Future<Session> insertSession(Session s, List<TrackPoint> pts) async {
    final db = await _open();
    final id = await db.transaction<int>((txn) async {
      final sid = await txn.insert('sessions', s.toMap());
      final batch = txn.batch();
      for (final pt in pts) {
        batch.insert('points', pt.toMap(sid));
      }
      await batch.commit(noResult: true);
      return sid;
    });
    return Session(
      id: id,
      type: s.type,
      startedAt: s.startedAt,
      endedAt: s.endedAt,
      distance: s.distance,
      duration: s.duration,
      maxSpeed: s.maxSpeed,
      avgSpeed: s.avgSpeed,
      pointCount: s.pointCount,
    );
  }

  /// 汇总统计：总里程、总时长、记录次数、记录天数
  static Future<Map<String, num>> totals() async {
    final db = await _open();
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(distance),0) AS dist,
             COALESCE(SUM(duration),0) AS dur,
             COUNT(*) AS cnt,
             COUNT(DISTINCT date(startedAt/1000, 'unixepoch', 'localtime')) AS days
      FROM sessions''');
    final r = rows.first;
    return {
      'distance': r['dist'] as num,
      'duration': r['dur'] as num,
      'count': r['cnt'] as num,
      'days': r['days'] as num,
    };
  }
}
