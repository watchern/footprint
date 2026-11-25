import 'dart:math' as math;

/// 判断一个定位时间戳是否足够「新鲜」。
///
/// Android 定位服务会优先下发系统缓存的「最后已知位置」，
/// 这个位置可能是几分钟甚至更久之前的，直接使用会导致地图跳到错误位置。
///
/// [timestampMs] 为定位时间戳（epoch 毫秒），[maxAgeMs] 为允许的最大年龄。
bool isPositionFresh(
  int timestampMs, {
  int maxAgeMs = 15000,
  int? nowMs,
}) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final age = now - timestampMs;
  return age <= maxAgeMs;
}

/// 两点间球面距离（米），输入 WGS-84 坐标
double haversine(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _rad(double d) => d * math.pi / 180.0;

bool _outOfChina(double lat, double lng) =>
    lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271;

double _transformLat(double x, double y) {
  double ret = -100.0 +
      2.0 * x +
      3.0 * y +
      0.2 * y * y +
      0.1 * x * y +
      0.2 * math.sqrt(x.abs());
  ret += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0;
  ret += (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) * 2.0 / 3.0;
  ret += (160.0 * math.sin(y / 12.0 * math.pi) + 320.0 * math.sin(y * math.pi / 30.0)) * 2.0 / 3.0;
  return ret;
}

double _transformLng(double x, double y) {
  double ret = 300.0 +
      x +
      2.0 * y +
      0.1 * x * x +
      0.1 * x * y +
      0.1 * math.sqrt(x.abs());
  ret += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0;
  ret += (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) * 2.0 / 3.0;
  ret += (150.0 * math.sin(x / 12.0 * math.pi) + 300.0 * math.sin(x / 30.0 * math.pi)) * 2.0 / 3.0;
  return ret;
}

/// WGS-84（GPS 原始坐标）→ GCJ-02（高德底图坐标），国测局标准纠偏算法，纯本地计算
List<double> wgs84ToGcj02(double lat, double lng) {
  if (_outOfChina(lat, lng)) return [lat, lng];
  double dLat = _transformLat(lng - 105.0, lat - 35.0);
  double dLng = _transformLng(lng - 105.0, lat - 35.0);
  final radLat = lat / 180.0 * math.pi;
  double magic = math.sin(radLat);
  magic = 1 - 0.00669342162296594323 * magic * magic;
  final sqrtMagic = math.sqrt(magic);
  dLat = (dLat * 180.0) /
      ((6378137.0 * (1 - 0.00669342162296594323)) / (magic * sqrtMagic) * math.pi);
  dLng = (dLng * 180.0) / (6378137.0 / sqrtMagic * math.cos(radLat) * math.pi);
  return [lat + dLat, lng + dLng];
}
