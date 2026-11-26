// Draws the app icon and writes every size the platforms need.
//
//   dart run tool/make_icons.dart
//
// Pure Dart with no packages: the shapes are drawn with signed distances
// (one sample per pixel, edges smoothed over a pixel), encoded as PNG with
// dart:io's zlib, and packed into a Windows .ico that holds PNGs.
//
// The icon: on the app's green, a smoothed trend line falling from top
// left to bottom right through a few faint dots (single weigh-ins),
// ending in a solid dot. Run again after changing anything here.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Palette.lightAccent, and a slightly lighter shade for the top.
const _accent = (0x2E, 0x6F, 0x57);
const _accentTop = (0x3B, 0x84, 0x69);

/// The trend line: a cubic Bezier in the unit square (y down).
const _p0 = (0.20, 0.30);
const _p1 = (0.47, 0.30);
const _p2 = (0.53, 0.70);
const _p3 = (0.80, 0.70);

/// Single weigh-ins around the line: centre and radius.
const _dots = [
  (0.27, 0.40, 0.034),
  (0.40, 0.25, 0.030),
  (0.42, 0.57, 0.032),
  (0.63, 0.77, 0.030),
  (0.72, 0.60, 0.028),
];

void main() {
  const res = 'android/app/src/main/res';
  // Legacy launcher icons: the whole rounded square.
  for (final (dir, px) in const [
    ('mipmap-mdpi', 48),
    ('mipmap-hdpi', 72),
    ('mipmap-xhdpi', 96),
    ('mipmap-xxhdpi', 144),
    ('mipmap-xxxhdpi', 192),
  ]) {
    _write('$res/$dir/ic_launcher.png', _png(_icon(px)));
  }
  // Adaptive icon foreground (108 dp, the glyph inside the 66 dp safe
  // zone); the background is a colour resource.
  for (final (dir, px) in const [
    ('mipmap-mdpi', 108),
    ('mipmap-hdpi', 162),
    ('mipmap-xhdpi', 216),
    ('mipmap-xxhdpi', 324),
    ('mipmap-xxxhdpi', 432),
  ]) {
    _write('$res/$dir/ic_launcher_foreground.png', _png(_foreground(px)));
  }
  // Windows: one .ico with every size Explorer and the taskbar ask for.
  _write(
    'windows/runner/resources/app_icon.ico',
    _ico([for (final px in const [16, 24, 32, 48, 64, 128, 256]) _icon(px)]),
  );
  // Google Play listing: 512 px, full square (Play rounds the corners).
  _write('docs/store/icon_512.png', _png(_icon(512, rounded: false)));
}

void _write(String path, List<int> bytes) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  stdout.writeln('wrote $path');
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

/// An RGBA image, straight (not premultiplied) alpha, 0–1 per channel.
class _Image {
  new(this.size) : rgba = Float64List(size * size * 4);

  final int size;
  final Float64List rgba;

  /// Paints colour [c] over pixel (x, y) with coverage [a].
  void over(int x, int y, (int, int, int) c, double a) {
    if (a <= 0) return;
    final i = (y * size + x) * 4;
    final da = rgba[i + 3];
    final oa = a + da * (1 - a);
    if (oa <= 0) return;
    final channels = [c.$1 / 255, c.$2 / 255, c.$3 / 255];
    for (var k = 0; k < 3; k++) {
      rgba[i + k] =
          (channels[k] * a + rgba[i + k] * da * (1 - a)) / oa;
    }
    rgba[i + 3] = oa;
  }
}

/// Coverage of a pixel whose centre is [d] (in pixels) from an edge,
/// negative inside.
double _cover(double d) => (0.5 - d).clamp(0.0, 1.0);

/// The full icon at [px] pixels: background and glyph.
_Image _icon(int px, {bool rounded = true}) {
  final img = _Image(px);
  final radius = rounded ? 0.22 : 0.0;
  for (var y = 0; y < px; y++) {
    for (var x = 0; x < px; x++) {
      final u = (x + 0.5) / px;
      final v = (y + 0.5) / px;
      final d = _roundedSquare(u, v, radius) * px;
      img.over(x, y, _mix(_accentTop, _accent, v), _cover(d));
    }
  }
  _glyph(img, scale: 1, details: px >= 32);
  return img;
}

/// The adaptive icon's foreground: the glyph alone, scaled into the
/// middle of a 108-unit square so it stays inside the 66-unit safe zone.
_Image _foreground(int px) {
  final img = _Image(px);
  _glyph(img, scale: 66 / 108 / 0.76, details: true);
  return img;
}

/// The trend line, its end dot and (when [details]) the weigh-ins, white,
/// drawn at [scale] about the centre. At 1 the glyph spans about 72% of
/// the square.
void _glyph(_Image img, {required double scale, required bool details}) {
  const white = (0xFF, 0xFF, 0xFF);
  final px = img.size;
  // Lines no thinner than 1.6 px, so small icons stay readable.
  final half = max(0.0375 * scale, 0.8 / px);
  final curve = _bezier(64);
  (double, double) toUnit(double u, double v) =>
      (0.5 + (u - 0.5) / scale, 0.5 + (v - 0.5) / scale);
  for (var y = 0; y < px; y++) {
    for (var x = 0; x < px; x++) {
      final (u, v) = toUnit((x + 0.5) / px, (y + 0.5) / px);
      if (details) {
        for (final (cx, cy, r) in _dots) {
          final d = (_dist(u, v, cx, cy) - r) * scale * px;
          img.over(x, y, white, _cover(d) * 0.45);
        }
      }
      final line = (_polylineDist(u, v, curve) - half / scale) * scale * px;
      img.over(x, y, white, _cover(line));
      final end = (_dist(u, v, _p3.$1, _p3.$2) - 0.068) * scale * px;
      img.over(x, y, white, _cover(end));
    }
  }
}

(int, int, int) _mix((int, int, int) a, (int, int, int) b, double t) => (
  (a.$1 + (b.$1 - a.$1) * t).round(),
  (a.$2 + (b.$2 - a.$2) * t).round(),
  (a.$3 + (b.$3 - a.$3) * t).round(),
);

double _dist(double x, double y, double cx, double cy) =>
    sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));

/// Signed distance to the unit square with corner [r], negative inside.
double _roundedSquare(double u, double v, double r) {
  final qx = (u - 0.5).abs() - (0.5 - r);
  final qy = (v - 0.5).abs() - (0.5 - r);
  final outside = sqrt(pow(max(qx, 0.0), 2) + pow(max(qy, 0.0), 2));
  return outside + min(max(qx, qy), 0.0) - r;
}

List<(double, double)> _bezier(int segments) => [
  for (var i = 0; i <= segments; i++)
    () {
      final t = i / segments;
      final s = 1 - t;
      return (
        s * s * s * _p0.$1 +
            3 * s * s * t * _p1.$1 +
            3 * s * t * t * _p2.$1 +
            t * t * t * _p3.$1,
        s * s * s * _p0.$2 +
            3 * s * s * t * _p1.$2 +
            3 * s * t * t * _p2.$2 +
            t * t * t * _p3.$2,
      );
    }(),
];

double _polylineDist(double x, double y, List<(double, double)> pts) {
  var best = double.infinity;
  for (var i = 0; i < pts.length - 1; i++) {
    final (ax, ay) = pts[i];
    final (bx, by) = pts[i + 1];
    final dx = bx - ax;
    final dy = by - ay;
    final t = (((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)).clamp(
      0.0,
      1.0,
    );
    best = min(best, _dist(x, y, ax + t * dx, ay + t * dy));
  }
  return best;
}

// ---------------------------------------------------------------------------
// Encoding
// ---------------------------------------------------------------------------

List<int> _png(_Image img) {
  final n = img.size;
  final raw = BytesBuilder();
  for (var y = 0; y < n; y++) {
    raw.addByte(0); // No filter.
    for (var x = 0; x < n; x++) {
      final i = (y * n + x) * 4;
      for (var k = 0; k < 4; k++) {
        raw.addByte((img.rgba[i + k] * 255).round().clamp(0, 255));
      }
    }
  }
  final header = ByteData(13)
    ..setUint32(0, n)
    ..setUint32(4, n)
    ..setUint8(8, 8) // Bit depth.
    ..setUint8(9, 6) // RGBA.
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  return [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    ..._chunk('IHDR', header.buffer.asUint8List()),
    ..._chunk('IDAT', ZLibEncoder(level: 9).convert(raw.takeBytes())),
    ..._chunk('IEND', const []),
  ];
}

List<int> _chunk(String type, List<int> data) {
  final typeBytes = type.codeUnits;
  final length = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, _crc32([...typeBytes, ...data]));
  return [
    ...length.buffer.asUint8List(),
    ...typeBytes,
    ...data,
    ...crc.buffer.asUint8List(),
  ];
}

final List<int> _crcTable = [
  for (var n = 0; n < 256; n++)
    () {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      return c;
    }(),
];

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

/// A .ico holding each image as a PNG (Windows Vista and later).
List<int> _ico(List<_Image> images) {
  final pngs = [for (final i in images) _png(i)];
  final head = ByteData(6 + 16 * images.length)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little) // Icon.
    ..setUint16(4, images.length, Endian.little);
  var offset = head.lengthInBytes;
  for (final (n, img) in images.indexed) {
    final e = 6 + 16 * n;
    final side = img.size >= 256 ? 0 : img.size; // 0 means 256.
    head
      ..setUint8(e, side)
      ..setUint8(e + 1, side)
      ..setUint8(e + 2, 0)
      ..setUint8(e + 3, 0)
      ..setUint16(e + 4, 1, Endian.little)
      ..setUint16(e + 6, 32, Endian.little)
      ..setUint32(e + 8, pngs[n].length, Endian.little)
      ..setUint32(e + 12, offset, Endian.little);
    offset += pngs[n].length;
  }
  return [...head.buffer.asUint8List(), for (final p in pngs) ...p];
}
