"""生成一个测试用 MBTiles 文件（2x2 瓦片，含 TMS 行号翻转），
用于验证离线地图包的读取与坐标映射逻辑。"""
import sqlite3, struct, zlib, os

def png(w, h, rgb):
    def chunk(typ, data):
        c = typ + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    raw = b''
    for y in range(h):
        raw += b'\x00' + bytes(rgb) * w
    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw))
            + chunk(b'IEND', b''))

path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'test_sample.mbtiles')
if os.path.exists(path):
    os.remove(path)

conn = sqlite3.connect(path)
conn.execute('CREATE TABLE metadata (name TEXT, value TEXT)')
conn.execute('CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB)')
conn.executemany('INSERT INTO metadata VALUES (?,?)', [
    ('name', 'test_offline'),
    ('type', 'overlay'),
    ('minzoom', '10'), ('maxzoom', '14'),
])
conn.execute('CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row)')

# zoom 12 下 4 张瓦片，x=3437..3438, y=1662..1663 (XYZ)
# MBTiles 存 TMS 行号：tms_y = 2^z - 1 - xyz_y
z = 12
for x in (3437, 3438):
    for y in (1662, 1663):
        tms_y = (1 << z) - 1 - y
        color = [(200, 30, 30), (30, 200, 30), (30, 30, 200), (200, 200, 30)][(x - 3437) * 2 + (y - 1662)]
        conn.execute('INSERT INTO tiles VALUES (?,?,?,?)', (z, x, tms_y, png(256, 256, color)))
conn.commit()
conn.close()
print('created:', path, os.path.getsize(path), 'bytes')
