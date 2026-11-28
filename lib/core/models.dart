/// 数据模型：全部字段纯本地，无任何云端结构
class Session {
  final int? id;
  final String type; // walk / run / bike / drive
  final int startedAt; // epoch ms
  final int? endedAt; // epoch ms
  final double distance; // 米（WGS-84 计算）
  final int duration; // 秒
  final double maxSpeed; // m/s
  final double avgSpeed; // m/s
  final int pointCount;

  const Session({
    this.id,
    required this.type,
    required this.startedAt,
    this.endedAt,
    required this.distance,
    required this.duration,
    required this.maxSpeed,
    required this.avgSpeed,
    required this.pointCount,
  });

  Map<String, Object?> toMap() => {
        'type': type,
        'startedAt': startedAt,
        'endedAt': endedAt,
        'distance': distance,
        'duration': duration,
        'maxSpeed': maxSpeed,
        'avgSpeed': avgSpeed,
        'pointCount': pointCount,
      };

  factory Session.fromMap(Map<String, Object?> m) => Session(
        id: m['id'] as int?,
        type: m['type'] as String,
        startedAt: m['startedAt'] as int,
        endedAt: m['endedAt'] as int?,
        distance: (m['distance'] as num?)?.toDouble() ?? 0,
        duration: (m['duration'] as num?)?.toInt() ?? 0,
        maxSpeed: (m['maxSpeed'] as num?)?.toDouble() ?? 0,
        avgSpeed: (m['avgSpeed'] as num?)?.toDouble() ?? 0,
        pointCount: (m['pointCount'] as num?)?.toInt() ?? 0,
      );
}

class TrackPoint {
  final int? id;
  final int sessionId;
  final double lat; // WGS-84
  final double lng; // WGS-84
  final int ts; // epoch ms
  final double speed; // m/s
  final double altitude; // 米

  const TrackPoint({
    this.id,
    required this.sessionId,
    required this.lat,
    required this.lng,
    required this.ts,
    required this.speed,
    required this.altitude,
  });

  Map<String, Object?> toMap(int sid) => {
        'sessionId': sid,
        'lat': lat,
        'lng': lng,
        'ts': ts,
        'speed': speed,
        'altitude': altitude,
      };

  factory TrackPoint.fromMap(Map<String, Object?> m) => TrackPoint(
        id: m['id'] as int?,
        sessionId: m['sessionId'] as int,
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        ts: m['ts'] as int,
        speed: (m['speed'] as num?)?.toDouble() ?? 0,
        altitude: (m['altitude'] as num?)?.toDouble() ?? 0,
      );
}

/// 出行类型：步行与跑步已合并为「行走」。
const Map<String, String> typeNames = {
  'walk': '行走',
  'bike': '骑行',
  'drive': '驾车',
};

const Map<String, int> typeColors = {
  'walk': 0xFF3B6D11, // 绿
  'bike': 0xFF185FA5, // 蓝
  'drive': 0xFF854F0B, // 棕金
};

/// 历史数据兼容：早期版本把「行走」拆成 walk/run 两种，
/// 现在统一合并。旧 run 记录不迁移数据，仅在读取时归一化为 walk。
String normalizeType(String raw) => raw == 'run' ? 'walk' : raw;

/// 取显示名（自动兼容历史类型）
String typeNameOf(String raw) => typeNames[normalizeType(raw)] ?? raw;

/// 取显示颜色（自动兼容历史类型）
int typeColorOf(String raw) =>
    typeColors[normalizeType(raw)] ?? 0xFF185FA5;

double kmh(double mps) => mps * 3.6;
