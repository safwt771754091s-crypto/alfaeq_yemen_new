import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Product images are up to 1080x1080. Decoded as raw RGBA that is 4.5 MB each,
/// and a grid cell renders at roughly 150 px. Without `cacheWidth` Flutter keeps
/// the full-size buffer in memory for every card on screen, which is the
/// difference between a smooth list and one that stutters or gets OOM-killed on
/// a low-end phone.
///
/// Server-side thumbnails are not available on this tenant (Supabase image
/// transformation returns 403 FeatureNotEnabled), so decoding at the display
/// size is the only lever. This test keeps new image widgets from forgetting it.
void main() {
  test('every Image.network decodes at its display size', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('Image.network')) continue;
        // A call may span lines; look ahead for the closing paren.
        final buffer = StringBuffer(lines[i]);
        var j = i;
        while (j < lines.length && j < i + 14 && !lines[j].trimRight().endsWith('),')) {
          j++;
          if (j < lines.length) buffer.write(lines[j]);
        }
        if (!buffer.toString().contains('cacheWidth')) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'add cacheWidth to these Image.network calls so full-resolution '
          'bitmaps are not decoded for small boxes: ${offenders.join(', ')}',
    );
  });

  test('every storage upload sets a cacheControl', () {
    // Supabase serves a public object with `private, no-cache` when the upload
    // does not set cacheControl, so the browser revalidates it on every view.
    // One uploader was missing this while the other eight set it.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('uploadBinary(')) continue;
        final buffer = StringBuffer(lines[i]);
        var j = i;
        while (j < lines.length && j < i + 12 && !lines[j].trimRight().endsWith(');')) {
          j++;
          if (j < lines.length) buffer.write(lines[j]);
        }
        if (!buffer.toString().contains('cacheControl')) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'these uploads would be served no-cache: ${offenders.join(', ')}',
    );
  });
}
