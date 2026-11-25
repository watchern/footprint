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
/// 4. **新鲜度校验**：Android 定位服务会优先下发系统缓存的「最后已知位置」，
///    取定位时必须校验时间戳，过旧的定位一律丢弃，否则地图会跳到旧位置。
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

  /// 当前定位的年龄（秒），null 表示无定位
  int? get positionAgeSeconds {
    final p = position;
    if (p == null) return null;
    final age =
        DateTime.now().millisecondsSinceEpoch - p.timestamp.millisecondsSinceEpoch;
    return age < 0 ? 0 : (age / 1000).round();
  }

  /// 定位是否新鲜（年龄在容忍范围内）
  bool isFresh([int maxAgeSeconds = 15]) {
    final age = positionAgeSeconds;
    return age != null && age <= maxAgeSeconds;
  }

  final StreamController<Position> _controller =
      StreamController<Position>.broadcast();

  /// 位置流（供运动记录订阅）
  Stream<Position> get positionStream => _controller.stream;

  StreamSubscription<Position>? _posSub;
  StreamSubscription<CompassEvent>? _compassSub;
  bool _permissionGranted = false;

  /// 检查定位权限是否已授予（不触发授权弹窗）
  Future<bool> hasPermission() async {
    if (_permissionGranted) return true;
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    final perm = await Geolocator.checkPermission();
    _permissionGranted = perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
    return _permissionGranted;
  }

  /// 请求定位权限（用户主动操作时调用）
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

  /// 开始持续定位。若权限未授予则不弹窗，直接返回 false（由调用方决定是否请求）。
  Future<bool> start({bool requestIfNeeded = false}) async {
    if (_posSub != null) return true;
    final allowed =
        requestIfNeeded ? await ensurePermission() : await hasPermission();
    if (!allowed) return false;

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

  /// 判断一个定位是否足够新（毫秒）
  bool _isFreshAt(Position p, int maxAgeMs) =>
      isPositionFresh(p.timestamp.millisecondsSinceEpoch, maxAgeMs: maxAgeMs);

  /// 立即获取一次当前位置。
  ///
  /// 注意：Android 的 `getCurrentPosition` 返回 provider 首次下发的位置，
  /// 该位置可能是系统缓存的「最后已知位置」（可能来自几分钟前）。
  /// 因此这里强制校验时间戳，过旧的定位直接判为无效（返回 null）。
  Future<Position?> refreshOnce({int maxAgeMs = 15000}) async {
    if (!await ensurePermission()) return null;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!_isFreshAt(p, maxAgeMs)) return null; // 缓存旧定位，丢弃
      position = p;
      _controller.add(p);
      notifyListeners();
      return p;
    } catch (_) {
      return null;
    }
  }

  /// 等待一个新鲜定位（来自持续定位流）。
  ///
  /// 用于「一次性取位返回了缓存旧定位」的场景：改从实时流中等待新点。
  Future<Position?> waitForFresh({
    Duration timeout = const Duration(seconds: 10),
    int maxAgeMs = 10000,
  }) {
    final completer = Completer<Position?>();
    StreamSubscription<Position>? sub;
    Timer? timer;

    void finish(Position? p) {
      if (!completer.isCompleted) completer.complete(p);
      sub?.cancel();
      timer?.cancel();
    }

    sub = _controller.stream.listen((p) {
      if (_isFreshAt(p, maxAgeMs)) finish(p);
    });
    timer = Timer(timeout, () => finish(null));
    return completer.future;
  }

  /// 获取用于「定位到当前位置」的可靠坐标。
  ///
  /// 策略：优先使用持续流中最新的新鲜定位；没有则主动取一次；
  /// 若取到的是缓存旧定位，则改为等待实时流下发新点。
  Future<Position?> acquireReliable({int maxAgeMs = 15000}) async {
    final p = position;
    if (p != null && _isFreshAt(p, maxAgeMs)) return p;

    final one = await refreshOnce(maxAgeMs: maxAgeMs);
    if (one != null) return one;

    // 一次性取位拿到的是缓存旧定位 → 等待实时流的新点
    return waitForFresh(maxAgeMs: maxAgeMs);
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
