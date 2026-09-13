import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// App-wide scroll behavior applied via [MaterialApp.scrollBehavior].
///
/// Two things it standardizes across every scrollable in the app:
///  * **Platform-appropriate momentum** — clamped on web for precise wheel and
///    trackpad input, with touch-style bounce retained by native builds.
///  * **Drag-to-scroll with any pointer** — enables mouse/trackpad/stylus
///    drag in addition to the default touch + wheel, which the Material
///    default omits on desktop and web.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    if (kIsWeb) {
      return const ClampingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
    }
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}
