import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

import 'geo.dart';

/// 位置服务：全应用唯一的 GPS 数据源。
///
/// 设计要点：
/// 1. **只存原始坐标**：对外暴露的一律是 WGS-84，坐标系转换交由渲染层按底图源决定。
/// 2. **朝向双来源**：优先使用罗盘（设备朝向，静止时依然有效），
///    无罗盘时回退到 GPS 航向（course over ground，移动时有效）。
/// 3. **单一订阅**：地图与运动记录共用同一条位置流，避免重复唤醒 GPS。
class LocationProvider extends ChangeNotifier {
  /// 最新位置（WGS-84 原始坐标）
  Position? position;

  /// 罗盘朝向（0-360，正北为 0），null 表示设备无罗盘
  double? compassHeading;

  /// GPS 航向（移动方向），静止时通常为 0 或无效
  double? courseHeading;

  /// 定位是否可用
  bool get hasFix => position != null;

  double? get latitude => position?.latitude;
  double? get longitude => position?.longitude;
  double? get accuracy => position?.accuracy;
  double? get speed => position?.speed;

  /// 综合朝向：罗盘优先，其次 GPS 航向
  double? get heading {
    final c = compassHeading;
    if (c != null) return c;
    final g = courseHeading;
    if (g != null && g > 0) return g;
    return null;
  }

  final StreamController<Position> _controller =
      StreamController<Position>.broadcast();

  /// 位置流（供运动记录订阅）
  Stream<Position> get positionStream => _controller.stream;

  StreamSubscription<Position>? _posSub;
  StreamSubscription<CompassEvent>? _compassSub;
  bool _permissionGranted = false;

  /// 确保定位权限已授予
  Future<bool> ensurePermission() async {
    if (_permissionGranted) return true;
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return false;
    }
    _permissionGranted = true;
    return true;
  }

  /// 开始持续定位
  Future<bool> start() async {
    if (_posSub != null) return true;
    if (!await ensurePermission()) return false;

    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      ),
    ).listen((p) {
      position = p;
      if (p.heading > 0) courseHeading = p.heading;
      _controller.add(p);
      notifyListeners();
    }, onError: (_) {});

    startCompass();
    return true;
  }

  /// 开始监听罗盘
  void startCompass() {
    if (_compassSub != null) return;
    try {
      _compassSub = FlutterCompass.events?.listen((e) {
        final h = e.heading;
        if (h != null) {
          compassHeading = h;
          notifyListeners();
        }
      }, onError: (_) {});
    } catch (_) {
      // 设备无罗盘传感器，忽略
    }
  }

  /// 停止定位与罗盘
  Future<void> stop() async {
    await _posSub?.cancel();
    _posSub = null;
    await _compassSub?.cancel();
    _compassSub = null;
  }

  /// 立即获取一次当前位置（用于「定位到当前位置」按钮）
  Future<Position?> refreshOnce() async {
    if (!await ensurePermission()) return null;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      position = p;
      _controller.add(p);
      notifyListeners();
      return p;
    } catch (_) {
      return null;
    }
  }

  /// 按给定坐标系返回当前点（渲染层使用）
  List<double>? displayPoint(bool isGcj02) {
    final p = position;
    if (p == null) return null;
    return isGcj02
        ? wgs84ToGcj02(p.latitude, p.longitude)
        : [p.latitude, p.longitude];
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _compassSub?.cancel();
    _controller.close();
    super.dispose();
  }
}
