import 'package:flutter/foundation.dart';

/// 底部标签页导航控制器。
///
/// 页面通过它互相跳转（例如「我的」页的累计足迹卡片跳到时间轴页），
/// 同时它也是各页面感知「自己被重新显示」的信号来源——用于触发数据刷新。
class AppNav extends ChangeNotifier {
  int _index = 0;

  /// 当前选中的标签页下标
  int get index => _index;

  /// 切换到指定标签页
  void goTo(int index) {
    if (index == _index) return;
    _index = index;
    notifyListeners();
  }
}
