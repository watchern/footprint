import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import 'geo.dart';

/// 坐标系定义。
///
/// 关键设计原则：**数据库中存储的永远是 WGS-84 原始 GPS 坐标**，
/// 坐标转换只在渲染层按当前底图源进行。这样切换底图（高德/腾讯/天地图/OSM）
/// 时无需迁移任何历史数据，也避免二次转换导致的坐标漂移。
enum CoordSystem {
  /// GPS 原始坐标（WGS-84）。OSM、天地图使用此坐标系。
  wgs84,

  /// 国测局加密坐标（GCJ-02）。高德、腾讯地图使用此坐标系。
  gcj02;

  String get label => this == wgs84 ? 'WGS-84' : 'GCJ-02';

  /// 将 WGS-84 原始坐标转换到本坐标系
  List<double> fromWgs84(double lat, double lng) =>
      this == wgs84 ? [lat, lng] : wgs84ToGcj02(lat, lng);
}

/// 一个可插拔的在线瓦片源。
///
/// 统一使用 XYZ 瓦片协议（{z}/{x}/{y}），这是 OSM 事实标准，
/// 天地图、高德、腾讯均支持或可映射到该协议，
/// 因此用户可以通过「镜像地址」替换任意源，格式保持一致。
class TileSource {
  final String id;
  final String name;

  /// XYZ 瓦片 URL 模板，占位符 {z}/{x}/{y}/{s}
  final String urlTemplate;

  /// 子域名列表，对应模板中的 {s}
  final List<String> subdomains;

  /// 该源使用的坐标系
  final CoordSystem coordSystem;

  /// 版权署名，地图下方必须展示
  final String attribution;

  /// 是否需要用户提供 API Key（如天地图）
  final bool requiresKey;

  /// 是否推荐（国内网络直连友好）
  final bool recommended;

  /// 该源可用的最大缩放级别。超过后瓦片请求返回空白/透明图。
  /// 实测：高德矢量 z=19 起返回 179 字节空白瓦片；卫星影像 z=19 仍正常。
  final int maxZoom;

  /// 备注说明
  final String? note;

  const TileSource({
    required this.id,
    required this.name,
    required this.urlTemplate,
    required this.subdomains,
    required this.coordSystem,
    required this.attribution,
    this.requiresKey = false,
    this.recommended = false,
    this.maxZoom = 18,
    this.note,
  });

  /// 天地图 WMTS 模板：{z}/{x}/{y} 映射为 TILEMATRIX/TILECOL/TILEROW
  static const tiandituTemplate =
      'https://t{s}.tianditu.gov.cn/vec_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=vec&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk={key}';

  /// 内置源列表。第一个为默认源。
  static const List<TileSource> builtin = [
    TileSource(
      id: 'amap',
      name: '高德矢量（推荐）',
      urlTemplate:
          'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
      subdomains: ['1', '2', '3', '4'],
      coordSystem: CoordSystem.gcj02,
      attribution: '© 高德地图',
      recommended: true,
      maxZoom: 18,
      note: '国内直连流畅，无需 Key，坐标为 GCJ-02',
    ),
    TileSource(
      id: 'amap_satellite',
      name: '高德卫星影像',
      urlTemplate:
          'https://webst0{s}.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}',
      subdomains: ['1', '2', '3', '4'],
      coordSystem: CoordSystem.gcj02,
      attribution: '© 高德地图',
      maxZoom: 19,
      note: '卫星影像 + 路网标注',
    ),
    TileSource(
      id: 'tianditu',
      name: '天地图（需 Key）',
      urlTemplate: tiandituTemplate,
      subdomains: ['0', '1', '2', '3', '4', '5', '6', '7'],
      coordSystem: CoordSystem.wgs84,
      attribution: '© 天地图',
      requiresKey: true,
      maxZoom: 18,
      note: '国家基础地理信息中心，坐标为 CGCS2000（近似 WGS-84）',
    ),
    TileSource(
      id: 'osm',
      name: 'OpenStreetMap',
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      subdomains: [],
      coordSystem: CoordSystem.wgs84,
      attribution: '© OpenStreetMap contributors',
      maxZoom: 19,
      note: '国内访问通常不稳定，建议改用镜像地址或在设置中填写自定义镜像',
    ),
  ];

  static TileSource byId(String id) =>
      builtin.firstWhere((e) => e.id == id, orElse: () => builtin.first);

  /// 生成一个 flutter_map 的 TileLayer。
  /// [template] 为空时使用本源的默认地址（可被用户自定义镜像覆盖）。
  TileLayer toTileLayer({String? template, String? keyValue}) {
    return TileLayer(
      key: ValueKey('$id-$template'),
      urlTemplate: template ?? urlTemplate,
      subdomains: subdomains,
      userAgentPackageName: 'local.local_footprints',
      additionalOptions: requiresKey && keyValue != null && keyValue.isNotEmpty
          ? {'key': keyValue}
          : const <String, String>{},
      maxNativeZoom: maxZoom,
    );
  }
}

/// 离线地图包（MBTiles）信息
class OfflinePackage {
  final String id;
  final String name;
  final String path;

  /// 该离线包覆盖的坐标系
  final CoordSystem coordSystem;
  final int minZoom;
  final int maxZoom;
  final int tileCount;
  final int sizeBytes;
  final DateTime importedAt;

  const OfflinePackage({
    required this.id,
    required this.name,
    required this.path,
    required this.coordSystem,
    required this.minZoom,
    required this.maxZoom,
    required this.tileCount,
    required this.sizeBytes,
    required this.importedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'path': path,
        'coordSystem': coordSystem.name,
        'minZoom': minZoom,
        'maxZoom': maxZoom,
        'tileCount': tileCount,
        'sizeBytes': sizeBytes,
        'importedAt': importedAt.millisecondsSinceEpoch,
      };

  factory OfflinePackage.fromMap(Map<String, dynamic> m) => OfflinePackage(
        id: m['id'] as String,
        name: m['name'] as String,
        path: m['path'] as String,
        coordSystem: CoordSystem.values.firstWhere(
          (e) => e.name == m['coordSystem'],
          orElse: () => CoordSystem.wgs84,
        ),
        minZoom: (m['minZoom'] as num).toInt(),
        maxZoom: (m['maxZoom'] as num).toInt(),
        tileCount: (m['tileCount'] as num).toInt(),
        sizeBytes: (m['sizeBytes'] as num).toInt(),
        importedAt:
            DateTime.fromMillisecondsSinceEpoch((m['importedAt'] as num).toInt()),
      );

  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
    }
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  }
}
