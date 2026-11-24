import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'db.dart';
import 'geo.dart';
import 'models.dart';

enum TrackState { idle, recording }

/// 运动记录控制器：GPS 采集 → 本地计算距离/速度 → 停止时一次性写入 SQLite。
/// 无任何网络上传。
class Tracker extends ChangeNotifier {
  TrackState state = TrackState.idle;
  String? type;
  DateTime? startTime;
  final List<TrackPoint> points = [];
  double distance = 0;
  double maxSpeed = 0;

  /// 最新一个点（GCJ-02，用于地图上跟随显示），null 表示暂无定位
  List<double>? currentGcj;
  double? currentSpeed;

  StreamSubscription<Position>? _sub;

  int get elapsedSeconds =>
      startTime == null ? 0 : DateTime.now().difference(startTime!).inSeconds;

  double get avgSpeed => elapsedSeconds > 0 ? distance / elapsedSeconds : 0;

  Future<bool> start(String t) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return false;
    }

    type = t;
    startTime = DateTime.now();
    points.clear();
    distance = 0;
    maxSpeed = 0;
    state = TrackState.recording;
    await WakelockPlus.enable();

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      ),
    ).listen(_onPosition, onError: (_) {});

    notifyListeners();
    return true;
  }

  void _onPosition(Position p) {
    final speed = (p.speed.isNaN || p.speed < 0) ? 0.0 : p.speed;
    if (p.latitude.isNaN || p.longitude.isNaN) return;
    final pt = TrackPoint(
      sessionId: 0, // 停止时统一回填
      lat: p.latitude,
      lng: p.longitude,
      ts: p.timestamp.millisecondsSinceEpoch,
      speed: speed,
      altitude: p.altitude.isNaN ? 0 : p.altitude,
    );
    if (points.isNotEmpty) {
      final last = points.last;
      final d = haversine(last.lat, last.lng, pt.lat, pt.lng);
      if (d < 1.0 && speed < 0.5) return; // 过滤原地抖动
      distance += d;
    }
    points.add(pt);
    if (speed > maxSpeed) maxSpeed = speed;
    currentGcj = wgs84ToGcj02(pt.lat, pt.lng);
    currentSpeed = speed;
    notifyListeners();
  }

  /// 停止并落库。返回保存后的 Session；点数不足时返回 null。
  Future<Session?> stop() async {
    await _sub?.cancel();
    _sub = null;
    await WakelockPlus.disable();
    state = TrackState.idle;
    final t = type ?? 'walk';
    final start = startTime;
    final pts = List<TrackPoint>.from(points);
    type = null;
    startTime = null;
    currentGcj = null;
    currentSpeed = null;
    points.clear();
    notifyListeners();

    if (start == null || pts.length < 2) return null;
    final ended = DateTime.now();
    final dur = ended.difference(start).inSeconds;
    if (dur <= 0) return null;
    final s = Session(
      type: t,
      startedAt: start.millisecondsSinceEpoch,
      endedAt: ended.millisecondsSinceEpoch,
      distance: distance,
      duration: dur,
      maxSpeed: maxSpeed,
      avgSpeed: distance / dur,
      pointCount: pts.length,
    );
    final saved = await AppDb.insertSession(s, pts);
    distance = 0;
    maxSpeed = 0;
    notifyListeners();
    return saved;
  }

  /// 放弃本次记录（不落库）
  Future<void> discard() async {
    await _sub?.cancel();
    _sub = null;
    await WakelockPlus.disable();
    state = TrackState.idle;
    type = null;
    startTime = null;
    currentGcj = null;
    currentSpeed = null;
    points.clear();
    distance = 0;
    maxSpeed = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }
}
