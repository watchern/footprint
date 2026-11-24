import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'db.dart';
import 'tile_source.dart';

/// 底图设置：源选择、自定义镜像、离线包管理。
/// 全部存储在本地 settings 表，无任何云端同步。
class MapSettings extends ChangeNotifier {
  String _sourceId = 'amap';

  /// 用户自定义镜像地址（OSM 或其他源的国内镜像），空表示用内置模板
  String _customUrlTemplate = '';

  /// 天地图 Key
  String _tiandituKey = '';

  /// 已导入的离线包
  List<OfflinePackage> _offlinePackages = [];

  /// 当前选中的离线包 id（启用离线模式）
  String? _activeOfflineId;

  bool _loaded = false;

  String get sourceId => _sourceId;
  String get customUrlTemplate => _customUrlTemplate;
  String get tiandituKey => _tiandituKey;
  List<OfflinePackage> get offlinePackages => List.unmodifiable(_offlinePackages);
  String? get activeOfflineId => _activeOfflineId;
  bool get loaded => _loaded;

  OfflinePackage? get activeOffline {
    if (_activeOfflineId == null) return null;
    for (final p in _offlinePackages) {
      if (p.id == _activeOfflineId) return p;
    }
    return null;
  }

  /// 是否处于离线底图模式
  bool get offlineMode => activeOffline != null;

  /// 当前在线源
  TileSource get source => TileSource.byId(_sourceId);

  /// 当前生效的坐标系：离线包优先，其次由在线源决定
  CoordSystem get coordSystem =>
      activeOffline?.coordSystem ?? source.coordSystem;

  /// 当前生效的瓦片 URL 模板（考虑用户自定义镜像）
  String get effectiveUrlTemplate {
    if (_customUrlTemplate.trim().isEmpty) return source.urlTemplate;
    return _customUrlTemplate.trim();
  }

  /// 是否使用了自定义镜像地址
  bool get usingCustomTemplate => _customUrlTemplate.trim().isNotEmpty;

  /// 生效的源描述（考虑自定义镜像）
  TileSource get effectiveSource {
    final s = source;
    if (!usingCustomTemplate) return s;
    return TileSource(
      id: s.id,
      name: s.name,
      urlTemplate: effectiveUrlTemplate,
      subdomains: s.subdomains,
      coordSystem: s.coordSystem,
      attribution: s.attribution,
      requiresKey: s.requiresKey,
      recommended: s.recommended,
      note: '已使用自定义镜像地址',
    );
  }

  Future<void> load() async {
    Future<String?> get(String k) => AppDb.getSetting(k);

    _sourceId = await get('map_source') ?? 'amap';
    _customUrlTemplate = await get('map_custom_url') ?? '';
    _tiandituKey = await get('map_tianditu_key') ?? '';
    final packs = await get('map_offline_packages');
    if (packs != null) {
      try {
        final list = jsonDecode(packs) as List;
        _offlinePackages = list
            .map((e) => OfflinePackage.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {
        _offlinePackages = [];
      }
    }
    _activeOfflineId = await get('map_active_offline');
    _loaded = true;
    notifyListeners();
  }

  Future<void> _set(String key, String value) =>
      AppDb.setSetting(key, value);

  Future<void> setSource(String id) async {
    _sourceId = id;
    await _set('map_source', id);
    notifyListeners();
  }

  Future<void> setCustomUrlTemplate(String tpl) async {
    _customUrlTemplate = tpl.trim();
    await _set('map_custom_url', _customUrlTemplate);
    notifyListeners();
  }

  Future<void> setTiandituKey(String key) async {
    _tiandituKey = key.trim();
    await _set('map_tianditu_key', _tiandituKey);
    notifyListeners();
  }

  Future<void> addOfflinePackage(OfflinePackage pkg) async {
    final existing = _offlinePackages.indexWhere((p) => p.id == pkg.id);
    if (existing >= 0) {
      _offlinePackages[existing] = pkg;
    } else {
      _offlinePackages.insert(0, pkg);
    }
    await _persistPackages();
    notifyListeners();
  }

  Future<void> removeOfflinePackage(String id) async {
    _offlinePackages.removeWhere((p) => p.id == id);
    if (_activeOfflineId == id) _activeOfflineId = null;
    await _persistPackages();
    await _set('map_active_offline', _activeOfflineId ?? '');
    notifyListeners();
  }

  Future<void> setActiveOffline(String? id) async {
    _activeOfflineId = id;
    await _set('map_active_offline', id ?? '');
    notifyListeners();
  }

  Future<void> _persistPackages() async {
    final json = jsonEncode(_offlinePackages.map((p) => p.toMap()).toList());
    await _set('map_offline_packages', json);
  }
}
