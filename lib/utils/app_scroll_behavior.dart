import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// App-wide scroll behavior applied via [MaterialApp.scrollBehavior].
///
/// Two things it standardizes across every scrollable in the app:
///  * **Momentum physics everywhere** — [BouncingScrollPhysics] on all
///    platforms (Flutter otherwise falls back to hard-stop
///    [ClampingScrollPhysics] on web/desktop), so lists feel fluid rather
///    than abruptly clamped.
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
    return const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
  }
}
