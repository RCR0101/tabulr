/// Shared machinery for `test/goldens/*_preview_test.dart`.
///
/// Those files render a widget and **write a PNG** rather than assert — the
/// image is the deliverable, so a design can be looked at instead of argued
/// about. Note that Material icons still render as `□`: there is no icon font
/// in the test environment.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> loadPreviewFont() async {
  final data = File('assets/fonts/Inter.ttf').readAsBytesSync();
  final loader = FontLoader('Inter')
    ..addFont(Future.value(ByteData.view(data.buffer)));
  await loader.load();
  await _loadMaterialIcons();
}

Future<void> _loadMaterialIcons() async {
  const relative = 'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
  for (var dir = File(Platform.resolvedExecutable).parent;
      dir.path != dir.parent.path;
      dir = dir.parent) {
    final font = File('${dir.path}/$relative');
    if (!font.existsSync()) continue;
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(font.readAsBytesSync().buffer)));
    return loader.load();
  }
}

/// The light/dark pair every preview renders.
const previewBrightnesses = <(String, Brightness)>[
  ('light', Brightness.light),
  ('dark', Brightness.dark),
];

ThemeData previewTheme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      brightness: brightness,
      colorSchemeSeed: const Color(0xFF58A6FF),
    );

/// Sizes the surface in *physical* pixels. 820 at a device pixel ratio of 2.0
/// is 410 logical — a phone, the tightest case worth previewing.
void usePreviewSurface(WidgetTester tester, Size physicalSize) {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// Captures the rendered frame to `test/goldens/<name>.png`.
Future<void> capturePreview(WidgetTester tester, String name) {
  return tester.runAsync(() async {
    final boundary = tester.firstRenderObject(find.byType(RepaintBoundary));
    final image = await (boundary as dynamic).toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('test/goldens/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
