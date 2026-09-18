import 'dart:convert';
import 'dart:typed_data';

/// SHA-1 hex digest of a UTF-8 string — the dedupe hash the notification
/// listener computes natively (`NoticeBuffer.hashFor`), reproduced here so
/// the Dart side can check a capture against stored notices before it
/// writes. Sixty lines beat a dependency for one call site.
String sha1Hex(String input) {
  final bytes = utf8.encode(input);
  final bitLength = bytes.length * 8;
  // Pad: 0x80, zeros to 56 mod 64, then the 64-bit big-endian bit length.
  final padded = BytesBuilder()
    ..add(bytes)
    ..addByte(0x80);
  while (padded.length % 64 != 56) {
    padded.addByte(0);
  }
  final lengthBytes = ByteData(8)..setUint64(0, bitLength, Endian.big);
  padded.add(lengthBytes.buffer.asUint8List());
  final data = padded.toBytes();

  var h0 = 0x67452301;
  var h1 = 0xEFCDAB89;
  var h2 = 0x98BADCFE;
  var h3 = 0x10325476;
  var h4 = 0xC3D2E1F0;

  final w = List<int>.filled(80, 0);
  for (var chunk = 0; chunk < data.length; chunk += 64) {
    for (var i = 0; i < 16; i++) {
      final j = chunk + i * 4;
      w[i] = (data[j] << 24) | (data[j + 1] << 16) | (data[j + 2] << 8) | data[j + 3];
    }
    for (var i = 16; i < 80; i++) {
      w[i] = _rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }
    var a = h0, b = h1, c = h2, d = h3, e = h4;
    for (var i = 0; i < 80; i++) {
      final int f;
      final int k;
      if (i < 20) {
        f = (b & c) | (~b & d);
        k = 0x5A827999;
      } else if (i < 40) {
        f = b ^ c ^ d;
        k = 0x6ED9EBA1;
      } else if (i < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8F1BBCDC;
      } else {
        f = b ^ c ^ d;
        k = 0xCA62C1D6;
      }
      final temp = (_rotl(a, 5) + (f & 0xFFFFFFFF) + e + k + w[i]) & 0xFFFFFFFF;
      e = d;
      d = c;
      c = _rotl(b, 30);
      b = a;
      a = temp;
    }
    h0 = (h0 + a) & 0xFFFFFFFF;
    h1 = (h1 + b) & 0xFFFFFFFF;
    h2 = (h2 + c) & 0xFFFFFFFF;
    h3 = (h3 + d) & 0xFFFFFFFF;
    h4 = (h4 + e) & 0xFFFFFFFF;
  }
  return [h0, h1, h2, h3, h4].map((v) => v.toRadixString(16).padLeft(8, '0')).join();
}

int _rotl(int x, int n) => ((x << n) | ((x & 0xFFFFFFFF) >> (32 - n))) & 0xFFFFFFFF;
