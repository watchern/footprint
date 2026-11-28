import 'package:flutter/foundation.dart';

/// 底部标签页导航控制器。
///
/// 页面通过它互相跳转（例如「我的」页的累计足迹卡片跳到时间轴页），
/// 同时它也是各页面感知「自己被重新显示」的信号来源——用于触发数据刷新。
class AppNav extends ChangeNotifier {
  /// 标签页总数（轨迹 / 时间轴 / 我的）。记录功能已并入轨迹页。
  static const int tabCount = 3;
  static const int tabMap = 0;
  static const int tabHistory = 1;
  static const int tabProfile = 2;

  int _index = 0;

  /// 当前选中的标签页下标
  int get index => _index;

  /// 切换到指定标签页（越界值会被钳制，避免 IndexedStack 报错）
  void goTo(int index) {
    final clamped = index < 0 ? 0 : (index >= tabCount ? tabCount - 1 : index);
    if (clamped == _index) return;
    _index = clamped;
    notifyListeners();
  }
}
