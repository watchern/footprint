import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:sqflite/sqflite.dart';

import 'tile_source.dart';

/// MBTiles 使用 TMS 行号（y 轴向下翻转），XYZ 协议中 y 轴向上。
/// 换算公式：tms_y = 2^z - 1 - xyz_y
int mbtilesRow(int z, int xyzY) => (1 << z) - 1 - xyzY;

/// MBTiles 离线地图包读取器。
///
/// MBTiles 是一个 SQLite 数据库，表结构：
///   tiles(zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB)
///   metadata(name TEXT, value TEXT)
///
/// 注意：MBTiles 的 tile_row 采用 TMS 编号（y 轴向下翻转），
/// 而 XYZ 瓦片协议中 y 轴向上，需做转换。
class MbTilesReader {
  final String path;
  Database? _db;
  bool _opened = false;

  MbTilesReader(this.path);

  Future<Database> _open() async {
    if (_opened && _db != null) return _db!;
    final db = await openDatabase(
      path,
      readOnly: true,
      singleInstance: true,
    );
    _db = db;
    _opened = true;
    return db;
  }

  /// 读取元数据
  Future<Map<String, String>> metadata() async {
    final db = await _open();
    final rows = await db.rawQuery('SELECT name, value FROM metadata');
    return {
      for (final r in rows) r['name'] as String: (r['value'] ?? '').toString()
    };
  }

  /// 读取瓦片二进制数据。返回 null 表示该瓦片不存在。
  Future<Uint8List?> tile(int z, int x, int y) async {
    try {
      final db = await _open();
      // MBTiles 使用 TMS 编号：row = 2^z - 1 - y
      final tmsY = mbtilesRow(z, y);
      final rows = await db.rawQuery(
        'SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=? LIMIT 1',
        [z, x, tmsY],
      );
      if (rows.isEmpty) return null;
      final data = rows.first['tile_data'];
      if (data is Uint8List) return data;
      if (data is List<int>) return Uint8List.fromList(data);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _opened = false;
  }
}

/// 从 MBTiles 读取瓦片的 flutter_map TileProvider
class MbTilesProvider extends TileProvider {
  final MbTilesReader reader;
  final int minZoom;
  final int maxZoom;

  MbTilesProvider({
    required this.reader,
    this.minZoom = 0,
    this.maxZoom = 19,
  });

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _MbTileImageProvider(
      reader: reader,
      z: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
  }
}

/// 单个离线瓦片的 ImageProvider
class _MbTileImageProvider extends ImageProvider<_MbTileImageProvider> {
  final MbTilesReader reader;
  final int z;
  final int x;
  final int y;
  final int minZoom;
  final int maxZoom;

  _MbTileImageProvider({
    required this.reader,
    required this.z,
    required this.x,
    required this.y,
    required this.minZoom,
    required this.maxZoom,
  });

  @override
  Future<_MbTileImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _MbTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _decode(key, decode),
      scale: 1,
      debugLabel: 'mbtiles ${key.z}/${key.x}/${key.y}',
    );
  }

  Future<ui.Codec> _decode(
    _MbTileImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    Uint8List? bytes;
    if (key.z >= key.minZoom && key.z <= key.maxZoom) {
      bytes = await key.reader.tile(key.z, key.x, key.y);
    }
    final buffer =
        await ui.ImmutableBuffer.fromUint8List(bytes ?? _transparentPng);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is _MbTileImageProvider &&
      other.z == z &&
      other.x == x &&
      other.y == y &&
      identical(other.reader, reader);

  @override
  int get hashCode => Object.hash(z, x, y, identityHashCode(reader));

  @override
  String toString() => 'MbTile($z, $x, $y)';
}

/// 1x1 透明 PNG
final Uint8List _transparentPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

/// 离线包导入与元信息解析
class OfflineImporter {
  /// 解析 MBTiles 文件元信息（不导入）
  static Future<OfflinePackage?> inspect(File file) async {
    try {
      final reader = MbTilesReader(file.path);
      final meta = await reader.metadata();
      final db = await openDatabase(file.path, readOnly: true, singleInstance: true);
      final countRows =
          await db.rawQuery('SELECT COUNT(*) AS c FROM tiles');
      final count = (countRows.first['c'] as num?)?.toInt() ?? 0;
      final zoomRows = await db
          .rawQuery('SELECT MIN(zoom_level) AS mn, MAX(zoom_level) AS mx FROM tiles');
      await db.close();
      await reader.close();

      final minZoom = (zoomRows.first['mn'] as num?)?.toInt() ?? 0;
      final maxZoom = (zoomRows.first['mx'] as num?)?.toInt() ?? 18;
      final name = meta['name']?.trim().isNotEmpty == true
          ? meta['name']!
          : file.uri.pathSegments.last;

      return OfflinePackage(
        id: file.path.hashCode.toRadixString(16),
        name: name,
        path: file.path,
        coordSystem: CoordSystem.wgs84,
        minZoom: minZoom,
        maxZoom: maxZoom,
        tileCount: count,
        sizeBytes: await file.length(),
        importedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}
