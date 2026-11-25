"""实测高德瓦片与 OSM 瓦片的地理对齐关系。

方法：
1. 取同一个 WGS-84 坐标，分别计算 高德瓦片 与 OSM瓦片 的 tile x/y（都用 WGS-84 算）
2. 下载两张图（256x256）
3. 用纯 Python 解码 PNG，做互相关，求出两张图之间的最佳像素偏移
4. 若偏移 ≈ 0  → 两张图内容一致，说明高德瓦片是 WGS-84 对齐
   若偏移 ≈ 500m 对应的像素数 → 高德瓦片是 GCJ-02 对齐（需要纠偏）
"""
import math, struct, zlib, urllib.request, sys

UA = {'User-Agent': 'Mozilla/5.0 (compatible; tile-test/1.0)'}


def fetch(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def decode_png(data):
    """返回 (w, h, [(r,g,b), ...]) 行优先像素列表"""
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'not a png'
    pos = 8
    w = h = bitd = ctype = None
    idat = b''
    while pos < len(data):
        ln = struct.unpack('>I', data[pos:pos + 4])[0]
        typ = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + ln]
        if typ == b'IHDR':
            w, h, bitd, ctype = struct.unpack('>IIBB', chunk[:10])
        elif typ == b'IDAT':
            idat += chunk
        elif typ == b'IEND':
            break
        pos += 12 + ln
    assert bitd == 8, f'unsupported bit depth {bitd}'
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = w * channels
    out = []
    prev = bytearray(stride)
    p = 0
    for _ in range(h):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        if f == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        row = []
        for x in range(w):
            o = x * channels
            if channels >= 3:
                row.append((line[o], line[o + 1], line[o + 2]))
            else:
                row.append((line[o], line[o], line[o]))
        out.append(row)
        prev = line
    return w, h, out


def deg2num(lat, lon, z):
    n = 2 ** z
    xt = int((lon + 180.0) / 360.0 * n)
    lat_rad = math.radians(lat)
    yt = int((1.0 - math.log(math.tan(lat_rad) + 1 / math.cos(lat_rad)) / math.pi) / 2.0 * n)
    return xt, yt


def wgs2gcj(lat, lng):
    if lng < 72.004 or lng > 137.8347 or lat < 0.8293 or lat > 55.8271:
        return lat, lng
    a, ee = 6378245.0, 0.00669342162296594323
    dlat = _tlat(lng - 105.0, lat - 35.0)
    dlng = _tlng(lng - 105.0, lat - 35.0)
    rad = lat / 180.0 * math.pi
    magic = math.sin(rad)
    magic = 1 - ee * magic * magic
    sq = math.sqrt(magic)
    dlat = (dlat * 180.0) / ((a * (1 - ee)) / (magic * sq) * math.pi)
    dlng = (dlng * 180.0) / (a / sq * math.cos(rad) * math.pi)
    return lat + dlat, lng + dlng


def _tlat(x, y):
    r = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * math.sqrt(abs(x))
    r += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0
    r += (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) * 2.0 / 3.0
    r += (160.0 * math.sin(y / 12.0 * math.pi) + 320 * math.sin(y * math.pi / 30.0)) * 2.0 / 3.0
    return r


def _tlng(x, y):
    r = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(abs(x))
    r += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0
    r += (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) * 2.0 / 3.0
    r += (150.0 * math.sin(x / 12.0 * math.pi) + 300.0 * math.sin(x / 30.0 * math.pi)) * 2.0 / 3.0
    return r


def best_shift(a, b, rng=90):
    """求 b 相对 a 的最佳 (dx,dy) 像素偏移（灰度 SAD 最小）"""
    def gray(img, w, h):
        return [[(p[0] * 299 + p[1] * 587 + p[2] * 114) // 1000 for p in row] for row in img]
    ga, gb = gray(a[2], a[0], a[1]), gray(b[2], b[0], b[1])
    best = None
    for dy in range(-rng, rng + 1, 2):
        for dx in range(-rng, rng + 1, 2):
            tot = 0; n = 0
            for y in range(30, 226, 8):
                ay = y
                by = y + dy
                if by < 0 or by >= 256: continue
                for x in range(30, 226, 8):
                    bx = x + dx
                    if bx < 0 or bx >= 256: continue
                    tot += abs(ga[ay][x] - gb[by][bx]); n += 1
            if n < 100: continue
            sad = tot / n
            if best is None or sad < best[0]:
                best = (sad, dx, dy)
    return best


if __name__ == '__main__':
    lat, lon, z = 39.9087, 116.3975, 15   # 北京天安门
    print(f'测试坐标 WGS-84: {lat}, {lon}  zoom={z}')

    x, y = deg2num(lat, lon, z)
    amap_url = (f'https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1'
                f'&style=8&x={x}&y={y}&z={z}')
    osm_url = f'https://tile.openstreetmap.de/{z}/{x}/{y}.png'
    print('高德瓦片:', amap_url)
    print('OSM瓦片 :', osm_url)

    amap = decode_png(fetch(amap_url))
    osm = decode_png(fetch(osm_url))
    print(f'解码完成: 高德 {amap[0]}x{amap[1]}, OSM {osm[0]}x{osm[1]}')

    sad, dx, dy = best_shift(amap, osm)
    mpp = 156543.03392804097 * math.cos(math.radians(lat)) / (2 ** z)
    print(f'\n最佳对齐偏移: dx={dx}px dy={dy}px  (SAD={sad:.1f})')
    print(f'该缩放级别每像素 ≈ {mpp:.2f} 米')
    print(f'换算偏移距离 ≈ {math.hypot(dx, dy) * mpp:.0f} 米')

    g_lat, g_lon = wgs2gcj(lat, lon)
    print(f'\n参考: WGS-84 → GCJ-02 理论偏移 = '
          f'{math.hypot((g_lat-lat)*111320, (g_lon-lon)*111320*math.cos(math.radians(lat))):.0f} 米')
