import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'db.dart';
import 'geo.dart';
import 'models.dart';

enum TrackState { idle, recording }

/// 运动记录控制器：GPS 采集 → 本地计算距离/速度 → 停止时一次性写入 SQLite。
///
/// 位置数据来自全局唯一的 [LocationProvider]，本控制器只负责采样与落库。
/// 无任何网络上传。
class Tracker extends ChangeNotifier {
  TrackState state = TrackState.idle;
  String? type;
  DateTime? startTime;
  final List<TrackPoint> points = [];
  double distance = 0;
  double maxSpeed = 0;

  /// 最新一个点（WGS-84 原始坐标）。坐标系转换由渲染层按底图源决定，此处不做纠偏。
  List<double>? currentWgs;
  double? currentSpeed;

  StreamSubscription<Position>? _sub;

  /// 每次成功保存一条记录后 +1，供时间轴页等监听数据变化
  int _revision = 0;

  /// 数据版本号（保存新记录后递增）
  int get revision => _revision;

  int get elapsedSeconds =>
      startTime == null ? 0 : DateTime.now().difference(startTime!).inSeconds;

  double get avgSpeed => elapsedSeconds > 0 ? distance / elapsedSeconds : 0;

  /// 开始记录。位置由 [LocationProvider] 的全局流提供。
  Future<bool> start(String t) async {
    type = t;
    startTime = DateTime.now();
    points.clear();
    distance = 0;
    maxSpeed = 0;
    state = TrackState.recording;
    await WakelockPlus.enable();
    notifyListeners();
    return true;
  }

  /// 绑定位置流
  void attachLocationStream(Stream<Position> stream) {
    _sub?.cancel();
    _sub = stream.listen(_onPosition, onError: (_) {});
  }

  void detachLocationStream() {
    _sub?.cancel();
    _sub = null;
  }

  void _onPosition(Position p) {
    if (state != TrackState.recording) return;
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
    currentWgs = [pt.lat, pt.lng];
    currentSpeed = speed;
    notifyListeners();
  }

  /// 停止并落库。返回保存后的 Session；点数不足时返回 null。
  Future<Session?> stop() async {
    detachLocationStream();
    await WakelockPlus.disable();
    state = TrackState.idle;
    final t = type ?? 'walk';
    final start = startTime;
    final pts = List<TrackPoint>.from(points);
    final dist = distance;
    final maxSp = maxSpeed;
    type = null;
    startTime = null;
    currentWgs = null;
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
      distance: dist,
      duration: dur,
      maxSpeed: maxSp,
      avgSpeed: dist / dur,
      pointCount: pts.length,
    );
    final saved = await AppDb.insertSession(s, pts);
    distance = 0;
    maxSpeed = 0;
    _revision++;
    notifyListeners();
    return saved;
  }

  /// 放弃本次记录（不落库）
  Future<void> discard() async {
    detachLocationStream();
    await WakelockPlus.disable();
    state = TrackState.idle;
    type = null;
    startTime = null;
    currentWgs = null;
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
