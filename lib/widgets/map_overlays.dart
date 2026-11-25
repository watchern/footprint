import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../core/scale.dart';

/// 地图比例尺（自绘）。
///
/// 放在 FlutterMap 的 children 中，通过 [MapCamera.of] 获取实时缩放级别与中心纬度，
/// 随地图缩放自动更新。左下角显示。
class ScaleBar extends StatelessWidget {
  /// 标尺最大像素宽度
  final double maxWidth;

  /// 额外的署名文字（地图版权要求）
  final String? attribution;

  const ScaleBar({super.key, this.maxWidth = kScaleBarMaxWidth, this.attribution});

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final mpp = metersPerPixel(camera.zoom, camera.center.latitude);
    final metric = pickScaleMetric(mpp, maxWidth);
    final barWidth = (metric / mpp).clamp(20.0, maxWidth);

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 10, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                formatScaleMetric(metric),
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 2),
            // 标尺横线：两端带竖线刻度
            SizedBox(
              width: barWidth,
              height: 8,
              child: CustomPaint(
                painter: _ScaleLinePainter(
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),
            if (attribution != null) ...[
              const SizedBox(height: 2),
              Text(
                attribution!,
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScaleLinePainter extends CustomPainter {
  final Color color;
  _ScaleLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final h = size.height;
    final w = size.width;
    canvas.drawLine(Offset(0, h), Offset(w, h), p);
    canvas.drawLine(Offset(0, 0), Offset(0, h), p);
    canvas.drawLine(Offset(w, 0), Offset(w, h), p);
  }

  @override
  bool shouldRepaint(covariant _ScaleLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 当前位置方向标。
///
/// 中心为定位点，外圈带精确度透明圆盘，箭头指示设备当前朝向。
/// 无朝向数据时（无罗盘且未移动）显示静态圆点。
class HeadingIndicator extends StatelessWidget {
  /// 朝向角度，0 为正北，顺时针增长
  final double? heading;

  /// 定位精度（米），用于绘制精确度圆盘
  final double? accuracy;

  final Color color;

  const HeadingIndicator({
    super.key,
    this.heading,
    this.accuracy,
    this.color = const Color(0xFF1A73E8),
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (accuracy != null && accuracy! > 0)
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
          ),
        Transform.rotate(
          angle: (heading ?? 0) * math.pi / 180.0,
          child: CustomPaint(
            size: const Size(36, 36),
            painter: _ArrowPainter(color: color),
          ),
        ),
      ],
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final Color color;
  _ArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // 箭头：指向正上方（正北），由外层 Transform.rotate 旋转
    final path = Path()
      ..moveTo(cx, 2)
      ..lineTo(cx + w * 0.36, cy + h * 0.22)
      ..lineTo(cx + w * 0.17, cy + h * 0.22)
      ..lineTo(cx + w * 0.17, h - 3)
      ..lineTo(cx - w * 0.17, h - 3)
      ..lineTo(cx - w * 0.17, cy + h * 0.22)
      ..lineTo(cx - w * 0.36, cy + h * 0.22)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );

    // 白色描边，保证在深色地图上清晰可见
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) =>
      oldDelegate.color != color;
}
