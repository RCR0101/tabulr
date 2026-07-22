import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import '../../constants/app_constants.dart';
import '../../models/screen_size.dart';

export '../../models/screen_size.dart';

class ResponsiveService {
  static const double mobileBreakpoint = ResponsiveConstants.mobileBreakpoint;
  static const double tabletBreakpoint = ResponsiveConstants.tabletBreakpoint;

  static const double minTouchTarget = ResponsiveConstants.minTouchTarget;
  static const double preferredTouchTarget = ResponsiveConstants.preferredTouchTarget;
  static const double largeTouchTarget = ResponsiveConstants.largeTouchTarget;

  static const double mobilePaddingScale = ResponsiveConstants.mobilePaddingScale;
  static const double tabletPaddingScale = ResponsiveConstants.tabletPaddingScale;
  static const double desktopPaddingScale = ResponsiveConstants.desktopPaddingScale;

  static const double mobileFontScale = ResponsiveConstants.mobileFontScale;
  static const double tabletFontScale = ResponsiveConstants.tabletFontScale;
  static const double desktopFontScale = ResponsiveConstants.desktopFontScale;

  static ScreenSize getScreenSize(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    if (width <= mobileBreakpoint) {
      return ScreenSize.mobile;
    } else if (width <= tabletBreakpoint) {
      return ScreenSize.tablet;
    } else {
      return ScreenSize.desktop;
    }
  }

  static double getScreenWidth(BuildContext context) {
    return MediaQuery.sizeOf(context).width;
  }

  static double getScreenHeight(BuildContext context) {
    return MediaQuery.sizeOf(context).height;
  }

  static bool isMobile(BuildContext context) {
    return getScreenSize(context) == ScreenSize.mobile;
  }

  static bool isTablet(BuildContext context) {
    return getScreenSize(context) == ScreenSize.tablet;
  }

  static bool isDesktop(BuildContext context) {
    return getScreenSize(context) == ScreenSize.desktop;
  }

  /// Mobile or tablet — i.e. touch-first devices.
  static bool isTouchDevice(BuildContext context) {
    final screenSize = getScreenSize(context);
    return screenSize == ScreenSize.mobile || screenSize == ScreenSize.tablet;
  }

  static ScreenOrientation getOrientation(BuildContext context) {
    final orientation = MediaQuery.orientationOf(context);
    return orientation.name == 'portrait'
        ? ScreenOrientation.portrait
        : ScreenOrientation.landscape;
  }

  static bool isLandscape(BuildContext context) {
    return getOrientation(context) == ScreenOrientation.landscape;
  }

  static bool isPortrait(BuildContext context) {
    return getOrientation(context) == ScreenOrientation.portrait;
  }

  static EdgeInsets getAdaptivePadding(BuildContext context, EdgeInsets basePadding) {
    final screenSize = getScreenSize(context);
    double scale;

    switch (screenSize) {
      case ScreenSize.mobile:
        scale = mobilePaddingScale;
        break;
      case ScreenSize.tablet:
        scale = tabletPaddingScale;
        break;
      case ScreenSize.desktop:
        scale = desktopPaddingScale;
        break;
    }

    return EdgeInsets.fromLTRB(
      basePadding.left * scale,
      basePadding.top * scale,
      basePadding.right * scale,
      basePadding.bottom * scale,
    );
  }

  static double getAdaptiveFontSize(BuildContext context, double baseFontSize) {
    final screenSize = getScreenSize(context);
    double scale;

    switch (screenSize) {
      case ScreenSize.mobile:
        scale = mobileFontScale;
        break;
      case ScreenSize.tablet:
        scale = tabletFontScale;
        break;
      case ScreenSize.desktop:
        scale = desktopFontScale;
        break;
    }

    return baseFontSize * scale;
  }

  static const double _mobileMinFontSize = ResponsiveConstants.mobileMinFontSize;

  /// Returns [baseFontSize] on desktop/tablet, but clamps to at least 11px on mobile.
  static double clampedFontSize(BuildContext context, double baseFontSize) {
    if (isMobile(context)) {
      return baseFontSize < _mobileMinFontSize ? _mobileMinFontSize : baseFontSize;
    }
    return baseFontSize;
  }

  static double getTouchTargetSize(BuildContext context) {
    final screenSize = getScreenSize(context);

    switch (screenSize) {
      case ScreenSize.mobile:
        return preferredTouchTarget;
      case ScreenSize.tablet:
        return largeTouchTarget;
      case ScreenSize.desktop:
        return minTouchTarget;
    }
  }

  static double getAdaptiveBorderRadius(BuildContext context, double baseBorderRadius) {
    final screenSize = getScreenSize(context);

    switch (screenSize) {
      case ScreenSize.mobile:
        return baseBorderRadius * 1.2; // Slightly larger for better touch
      case ScreenSize.tablet:
        return baseBorderRadius * 1.1;
      case ScreenSize.desktop:
        return baseBorderRadius;
    }
  }

  static double getAdaptiveIconSize(BuildContext context, double baseIconSize) {
    final screenSize = getScreenSize(context);

    switch (screenSize) {
      case ScreenSize.mobile:
        return baseIconSize * 1.1; // Slightly larger for better visibility
      case ScreenSize.tablet:
        return baseIconSize * 1.05;
      case ScreenSize.desktop:
        return baseIconSize;
    }
  }

  static int getGridColumns(BuildContext context, {
    int mobileColumns = 1,
    int tabletColumns = 2,
    int desktopColumns = 3,
  }) {
    final screenSize = getScreenSize(context);

    switch (screenSize) {
      case ScreenSize.mobile:
        return mobileColumns;
      case ScreenSize.tablet:
        return tabletColumns;
      case ScreenSize.desktop:
        return desktopColumns;
    }
  }

  static double getAdaptiveSpacing(BuildContext context, double baseSpacing) {
    final screenSize = getScreenSize(context);

    switch (screenSize) {
      case ScreenSize.mobile:
        return baseSpacing * 0.8; // Tighter spacing on mobile
      case ScreenSize.tablet:
        return baseSpacing * 0.9;
      case ScreenSize.desktop:
        return baseSpacing;
    }
  }

  static bool isKeyboardVisible(BuildContext context) {
    return MediaQuery.viewInsetsOf(context).bottom > 0;
  }

  static EdgeInsets getSafeAreaPadding(BuildContext context) {
    return MediaQuery.paddingOf(context);
  }

  static EdgeInsets getViewInsets(BuildContext context) {
    return MediaQuery.viewInsetsOf(context);
  }

  static double getDevicePixelRatio(BuildContext context) {
    return MediaQuery.devicePixelRatioOf(context);
  }

  /// Returns the user's full system text scale, unclamped, so the app honours
  /// accessibility font-size preferences.
  static double getTextScaleFactor(BuildContext context) {
    return MediaQuery.textScalerOf(context).scale(1.0);
  }

  /// Returns [mobile]/[tablet]/[desktop] for the current screen, falling back
  /// to the next-smaller value when a larger one is omitted.
  static T getValue<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    final screenSize = getScreenSize(context);

    switch (screenSize) {
      case ScreenSize.mobile:
        return mobile;
      case ScreenSize.tablet:
        return tablet ?? mobile;
      case ScreenSize.desktop:
        return desktop ?? tablet ?? mobile;
    }
  }

  static Widget buildResponsive(
    BuildContext context, {
    required Widget mobile,
    Widget? tablet,
    Widget? desktop,
  }) {
    final screenSize = getScreenSize(context);

    switch (screenSize) {
      case ScreenSize.mobile:
        return mobile;
      case ScreenSize.tablet:
        return tablet ?? mobile;
      case ScreenSize.desktop:
        return desktop ?? tablet ?? mobile;
    }
  }

  static double getMaxContentWidth(BuildContext context) {
    final screenSize = getScreenSize(context);

    switch (screenSize) {
      case ScreenSize.mobile:
        return double.infinity; // Full width on mobile
      case ScreenSize.tablet:
        return 768.0;
      case ScreenSize.desktop:
        return 1200.0;
    }
  }

  static bool shouldCollapseAppBar(BuildContext context) {
    return isMobile(context) && isPortrait(context);
  }

  static bool shouldUseFullScreenDialog(BuildContext context) {
    return isMobile(context) && isPortrait(context);
  }

  static double getAppBarHeight(BuildContext context) {
    final screenSize = getScreenSize(context);

    switch (screenSize) {
      case ScreenSize.mobile:
        return 56.0;
      case ScreenSize.tablet:
        return 64.0;
      case ScreenSize.desktop:
        return 72.0;
    }
  }

  static void triggerLightFeedback(BuildContext context) {
    if (isMobile(context)) {
      HapticFeedback.lightImpact();
    }
  }

  static void triggerMediumFeedback(BuildContext context) {
    if (isMobile(context)) {
      HapticFeedback.mediumImpact();
    }
  }

  static void triggerHeavyFeedback(BuildContext context) {
    if (isMobile(context)) {
      HapticFeedback.heavyImpact();
    }
  }

  static void triggerSelectionFeedback(BuildContext context) {
    if (isMobile(context)) {
      HapticFeedback.selectionClick();
    }
  }

  static void triggerVibrate(BuildContext context) {
    if (isMobile(context)) {
      HapticFeedback.vibrate();
    }
  }

  static Duration getLongPressDuration(BuildContext context) {
    return isMobile(context)
      ? const Duration(milliseconds: 500)
      : const Duration(milliseconds: 400);
  }

  static Widget buildPerformantWidget({
    required BuildContext context,
    required Widget child,
    bool forceRepaintBoundary = false,
  }) {
    // Use RepaintBoundary on mobile devices or when forced
    final shouldUseRepaintBoundary = forceRepaintBoundary || isMobile(context);

    if (shouldUseRepaintBoundary) {
      return RepaintBoundary(child: child);
    }
    return child;
  }

  /// Get appropriate scroll physics for the platform.
  ///
  /// Defaults to momentum-based [BouncingScrollPhysics] on every platform to
  /// match the app-wide `AppScrollBehavior`, so lists feel fluid instead of
  /// hard-clamping on desktop/web. Pass `bouncing: false` for the rare case
  /// where a clamped scroll is desired.
  static ScrollPhysics getScrollPhysics(BuildContext context, {
    bool bouncing = true,
  }) {
    return bouncing
      ? const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())
      : const ClampingScrollPhysics();
  }

  static Widget buildOptimizedListView({
    required BuildContext context,
    required IndexedWidgetBuilder itemBuilder,
    required int itemCount,
    ScrollController? controller,
    EdgeInsets? padding,
    bool shrinkWrap = false,
  }) {
    return ListView.builder(
      controller: controller,
      physics: getScrollPhysics(context),
      padding: padding,
      shrinkWrap: shrinkWrap,
      itemCount: itemCount,
      scrollCacheExtent: ScrollCacheExtent.pixels(isMobile(context) ? 250.0 : 500.0),
      itemBuilder: (context, index) {
        return buildPerformantWidget(
          context: context,
          child: itemBuilder(context, index),
        );
      },
    );
  }

}

/// Extension methods for easier access
extension ResponsiveContext on BuildContext {
  ScreenSize get screenSize => ResponsiveService.getScreenSize(this);
  bool get isMobile => ResponsiveService.isMobile(this);
  bool get isTablet => ResponsiveService.isTablet(this);
  bool get isDesktop => ResponsiveService.isDesktop(this);
  bool get isTouchDevice => ResponsiveService.isTouchDevice(this);
  bool get isLandscape => ResponsiveService.isLandscape(this);
  bool get isPortrait => ResponsiveService.isPortrait(this);
  bool get isKeyboardVisible => ResponsiveService.isKeyboardVisible(this);
  double get screenWidth => ResponsiveService.getScreenWidth(this);
  double get screenHeight => ResponsiveService.getScreenHeight(this);
  double get touchTargetSize => ResponsiveService.getTouchTargetSize(this);
  EdgeInsets get safeAreaPadding => ResponsiveService.getSafeAreaPadding(this);
  EdgeInsets get viewInsets => ResponsiveService.getViewInsets(this);
  double get devicePixelRatio => ResponsiveService.getDevicePixelRatio(this);
  double get textScaleFactor => ResponsiveService.getTextScaleFactor(this);

  // Haptic feedback convenience methods
  void triggerLightFeedback() => ResponsiveService.triggerLightFeedback(this);
  void triggerMediumFeedback() => ResponsiveService.triggerMediumFeedback(this);
  void triggerHeavyFeedback() => ResponsiveService.triggerHeavyFeedback(this);
  void triggerSelectionFeedback() => ResponsiveService.triggerSelectionFeedback(this);
  void triggerVibrate() => ResponsiveService.triggerVibrate(this);
}
