/// 中文日期文本格式化。
///
/// 刻意不依赖 `intl` 的 locale 数据：`DateFormat(pattern, 'zh_CN')` 需要先调用
/// `initializeDateFormatting('zh_CN')`，否则会抛 LocaleDataException，
/// 导致列表项构建失败（表现为列表一片空白）。
/// 这里直接自行格式化，彻底消除该依赖。
library;

const List<String> _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

/// 格式化为「2026年11月28日 星期六」
String formatChineseDay(DateTime d) {
  final weekday = _weekdayNames[(d.weekday - 1) % 7];
  return '${d.year}年${d.month}月${d.day}日 星期$weekday';
}

/// 格式化为「14:30」（24 小时制）
String formatClockTime(DateTime d) {
  final h = d.hour.toString().padLeft(2, '0');
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// 格式化为「2026-11-28 14:30」
String formatDateTime(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final mo = d.month.toString().padLeft(2, '0');
  final da = d.day.toString().padLeft(2, '0');
  return '$y-$mo-$da ${formatClockTime(d)}';
}
