import 'dart:math' as math;

/// 比例尺计算。
///
/// 采用 Web Mercator 标准公式（256px 瓦片）：
///   米/像素 = 156543.03392804097 × cos(纬度) / 2^zoom
///
/// 该模块为纯函数，便于单元测试。

/// 比例尺最大像素宽度（标尺横条的目标长度）。
///
/// 「定位到当前位置」按钮使用同一常量反解缩放级别，
/// 确保定位后比例尺读数恰好为 500 米。
const double kScaleBarMaxWidth = 90;

/// 指定缩放级别与纬度下，每像素代表的米数。
double metersPerPixel(double zoom, double latitude) {
  final latRad = latitude * math.pi / 180.0;
  return 156543.03392804097 * math.cos(latRad) / math.pow(2.0, zoom);
}

/// 候选刻度值（米），按升序排列。
const List<double> scaleMetrics = [
  1, 2, 5, 10, 20, 50, //
  100, 200, 500, 1000, 2000, 5000,
  10000, 20000, 50000, 100000, 200000, 500000, 1000000,
];

/// 从候选刻度中选出「宽度不超过 [maxWidth] 像素」的最大值。
/// 若全部超出，则返回最小候选值。
double pickScaleMetric(double metersPerPixel, double maxWidth) {
  // 容差：吸收浮点误差，保证恰好等于 maxWidth 的候选能被选中
  const eps = 1e-9;
  double? best;
  for (final m in scaleMetrics) {
    if (m / metersPerPixel <= maxWidth + eps) {
      best = m;
    }
  }
  return best ?? scaleMetrics.first;
}

/// 反解：使比例尺读数恰好为 [targetMeters] 时的缩放级别。
///
/// 推导：要让 target 被选中且更大的刻度不被选中，需满足
///   target / mpp ≤ maxWidth  且  next / mpp > maxWidth
/// 即 mpp ∈ [target/maxWidth, next/maxWidth)。
/// 取下边界即可（拾取时的 epsilon 会吸收浮点误差）。
double zoomForScaleMetric(
  double targetMeters,
  double latitude,
  double maxWidth,
) {
  final mpp = targetMeters / maxWidth;
  final latRad = latitude * math.pi / 180.0;
  final raw = 156543.03392804097 * math.cos(latRad) / mpp;
  return math.log(raw) / math.ln2;
}

/// 格式化刻度文本。
String formatScaleMetric(double meters) {
  if (meters < 1000) {
    return '${meters.round()} m';
  }
  final km = meters / 1000;
  if (km < 10) {
    return '${km.toStringAsFixed(km % 1 == 0 ? 0 : 1)} km';
  }
  return '${km.round()} km';
}
