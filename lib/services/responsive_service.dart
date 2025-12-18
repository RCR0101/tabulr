import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum ScreenSize {
  mobile,    // ≤ 600px
  tablet,    // 601px - 900px  
  desktop,   // > 900px
}

enum Orientation {
  portrait,
  landscape,
}

class ResponsiveService {
  static const double mobileBreakpoint = 600.0;
  static const double tabletBreakpoint = 900.0;
  
  // Touch target sizes
  static const double minTouchTarget = 48.0;
  static const double preferredTouchTarget = 56.0;
  static const double largeTouchTarget = 64.0;
  
  // Padding and margin scales
  static const double mobilePaddingScale = 0.75;
  static const double tabletPaddingScale = 0.9;
  static const double desktopPaddingScale = 1.0;
  
  // Font size scales
  static const double mobileFontScale = 0.9;
  static const double tabletFontScale = 0.95;
  static const double desktopFontScale = 1.0;

  /// Get current screen size category
  static ScreenSize getScreenSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    
    if (width <= mobileBreakpoint) {
      return ScreenSize.mobile;
    } else if (width <= tabletBreakpoint) {
      return ScreenSize.tablet;
    } else {
      return ScreenSize.desktop;
    }
  }
  
  /// Get screen width
  static double getScreenWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }
  
  /// Get screen height
  static double getScreenHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }
  
  /// Check if current screen is mobile size
  static bool isMobile(BuildContext context) {
    return getScreenSize(context) == ScreenSize.mobile;
  }
  
  /// Check if current screen is tablet size
  static bool isTablet(BuildContext context) {
    return getScreenSize(context) == ScreenSize.tablet;
  }
  
  /// Check if current screen is desktop size
  static bool isDesktop(BuildContext context) {
    return getScreenSize(context) == ScreenSize.desktop;
  }
  
  /// Check if screen is mobile or tablet (touch-first devices)
  static bool isTouchDevice(BuildContext context) {
    final screenSize = getScreenSize(context);
    return screenSize == ScreenSize.mobile || screenSize == ScreenSize.tablet;
  }
  
  /// Get orientation
  static Orientation getOrientation(BuildContext context) {
    final orientation = MediaQuery.orientationOf(context);
    return orientation.name == 'portrait'
        ? Orientation.portrait 
        : Orientation.landscape;
  }
  
  /// Check if device is in landscape mode
  static bool isLandscape(BuildContext context) {
    return getOrientation(context) == Orientation.landscape;
  }
  
  /// Check if device is in portrait mode
  static bool isPortrait(BuildContext context) {
    return getOrientation(context) == Orientation.portrait;
  }
  
  /// Get adaptive padding based on screen size
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
  
  /// Get adaptive margin based on screen size
  static EdgeInsets getAdaptiveMargin(BuildContext context, EdgeInsets baseMargin) {
    return getAdaptivePadding(context, baseMargin); // Same logic as padding
  }
  
  /// Get adaptive font size based on screen size
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
  
  /// Get minimum touch target size for current screen
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
  
  /// Get adaptive border radius based on screen size
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
  
  /// Get adaptive elevation based on screen size
  static double getAdaptiveElevation(BuildContext context, double baseElevation) {
    final screenSize = getScreenSize(context);
    
    switch (screenSize) {
      case ScreenSize.mobile:
        return baseElevation * 1.5; // More pronounced shadows on mobile
      case ScreenSize.tablet:
        return baseElevation * 1.2;
      case ScreenSize.desktop:
        return baseElevation;
    }
  }
  
  /// Get adaptive icon size based on screen size
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
  
  /// Get number of columns for grid layouts
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
  
  /// Get adaptive spacing based on screen size
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
  
  /// Check if keyboard is visible
  static bool isKeyboardVisible(BuildContext context) {
    return MediaQuery.of(context).viewInsets.bottom > 0;
  }
  
  /// Get safe area padding
  static EdgeInsets getSafeAreaPadding(BuildContext context) {
    return MediaQuery.of(context).padding;
  }
  
  /// Get view insets (keyboard, etc.)
  static EdgeInsets getViewInsets(BuildContext context) {
    return MediaQuery.of(context).viewInsets;
  }
  
  /// Get device pixel ratio
  static double getDevicePixelRatio(BuildContext context) {
    return MediaQuery.of(context).devicePixelRatio;
  }
  
  /// Get text scale factor
  static double getTextScaleFactor(BuildContext context) {
    return MediaQuery.textScalerOf(context).scale(1.0).clamp(0.8, 1.3);
  }
  
  /// Responsive value helper - returns different values for different screen sizes
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
  
  /// Build responsive widget - different widgets for different screen sizes
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
  
  /// Get maximum content width for centered layouts
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
  
  /// Check if app bar should be collapsed on mobile
  static bool shouldCollapseAppBar(BuildContext context) {
    return isMobile(context) && isPortrait(context);
  }
  
  /// Get appropriate dialog type for screen size
  static bool shouldUseFullScreenDialog(BuildContext context) {
    return isMobile(context) && isPortrait(context);
  }
  
  /// Get adaptive app bar height
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
  
  // ========== Haptic Feedback Support ==========
  
  /// Trigger light haptic feedback for mobile devices
  static void triggerLightFeedback(BuildContext context) {
    if (isMobile(context)) {
      HapticFeedback.lightImpact();
    }
  }
  
  /// Trigger medium haptic feedback for mobile devices
  static void triggerMediumFeedback(BuildContext context) {
    if (isMobile(context)) {
      HapticFeedback.mediumImpact();
    }
  }
  
  /// Trigger heavy haptic feedback for mobile devices
  static void triggerHeavyFeedback(BuildContext context) {
    if (isMobile(context)) {
      HapticFeedback.heavyImpact();
    }
  }
  
  /// Trigger selection feedback (for buttons, toggles, etc.)
  static void triggerSelectionFeedback(BuildContext context) {
    if (isMobile(context)) {
      HapticFeedback.selectionClick();
    }
  }
  
  /// Trigger vibrate for important actions
  static void triggerVibrate(BuildContext context) {
    if (isMobile(context)) {
      HapticFeedback.vibrate();
    }
  }
  
  // ========== Gesture Support ==========
  
  /// Get appropriate gesture velocity threshold for swipe detection
  static double getSwipeVelocityThreshold(BuildContext context) {
    return isMobile(context) ? 1000.0 : 500.0;
  }
  
  /// Get appropriate gesture distance threshold for swipe detection
  static double getSwipeDistanceThreshold(BuildContext context) {
    return isMobile(context) ? 50.0 : 30.0;
  }
  
  /// Get double tap timeout duration
  static Duration getDoubleTapTimeout(BuildContext context) {
    return const Duration(milliseconds: 300);
  }
  
  /// Get long press duration
  static Duration getLongPressDuration(BuildContext context) {
    return isMobile(context) 
      ? const Duration(milliseconds: 500)
      : const Duration(milliseconds: 400);
  }
  
  /// Create a gesture detector with mobile-optimized settings
  static Widget buildResponsiveGestureDetector({
    required BuildContext context,
    required Widget child,
    VoidCallback? onTap,
    VoidCallback? onDoubleTap,
    VoidCallback? onLongPress,
    GestureDragUpdateCallback? onPanUpdate,
    GestureDragEndCallback? onPanEnd,
    bool enableHapticFeedback = true,
  }) {
    return GestureDetector(
      onTap: onTap == null ? null : () {
        if (enableHapticFeedback) triggerSelectionFeedback(context);
        onTap();
      },
      onDoubleTap: onDoubleTap == null ? null : () {
        if (enableHapticFeedback) triggerMediumFeedback(context);
        onDoubleTap();
      },
      onLongPress: onLongPress == null ? null : () {
        if (enableHapticFeedback) triggerHeavyFeedback(context);
        onLongPress();
      },
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      child: child,
    );
  }
  
  // ========== Performance Optimizations ==========
  
  /// Wrap widget with RepaintBoundary for performance optimization
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
  
  /// Get appropriate scroll physics for the platform
  static ScrollPhysics getScrollPhysics(BuildContext context, {
    bool bouncing = true,
  }) {
    if (isMobile(context)) {
      return bouncing 
        ? const BouncingScrollPhysics()
        : const ClampingScrollPhysics();
    }
    return const ClampingScrollPhysics();
  }
  
  /// Build an optimized ListView for mobile performance
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
      cacheExtent: isMobile(context) ? 250.0 : 500.0, // Smaller cache on mobile
      itemBuilder: (context, index) {
        return buildPerformantWidget(
          context: context,
          child: itemBuilder(context, index),
        );
      },
    );
  }
  
  /// Build an optimized GridView for mobile performance
  static Widget buildOptimizedGridView({
    required BuildContext context,
    required IndexedWidgetBuilder itemBuilder,
    required int itemCount,
    required SliverGridDelegate gridDelegate,
    ScrollController? controller,
    EdgeInsets? padding,
    bool shrinkWrap = false,
  }) {
    return GridView.builder(
      controller: controller,
      physics: getScrollPhysics(context),
      padding: padding,
      shrinkWrap: shrinkWrap,
      gridDelegate: gridDelegate,
      itemCount: itemCount,
      cacheExtent: isMobile(context) ? 200.0 : 400.0, // Smaller cache on mobile
      itemBuilder: (context, index) {
        return buildPerformantWidget(
          context: context,
          child: itemBuilder(context, index),
        );
      },
    );
  }
  
  // ========== Accessibility Support ==========
  
  /// Get semantic label based on context and screen size
  static String getAccessibilityLabel(BuildContext context, String baseLabel) {
    if (isMobile(context)) {
      return '$baseLabel - tap to interact';
    }
    return baseLabel;
  }
  
  /// Build accessible button with proper semantics
  static Widget buildAccessibleButton({
    required BuildContext context,
    required Widget child,
    required VoidCallback onPressed,
    String? semanticLabel,
    String? tooltip,
    bool excludeSemantics = false,
  }) {
    Widget button = child;
    
    if (tooltip != null) {
      button = Tooltip(
        message: tooltip,
        child: button,
      );
    }
    
    if (semanticLabel != null && !excludeSemantics) {
      button = Semantics(
        label: getAccessibilityLabel(context, semanticLabel),
        button: true,
        enabled: true,
        child: button,
      );
    }
    
    return button;
  }
  
  /// Get appropriate contrast ratio for the screen
  static double getContrastRatio(BuildContext context) {
    // Higher contrast needed on mobile due to varying lighting conditions
    return isMobile(context) ? 4.5 : 3.0;
  }
  
  /// Check if large text scale is being used
  static bool isLargeTextScale(BuildContext context) {
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);
    return textScaleFactor > 1.3;
  }
  
  /// Get accessible text style that adapts to text scaling
  static TextStyle getAccessibleTextStyle(BuildContext context, {
    double fontSize = 14.0,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
  }) {
    final textScaler = MediaQuery.textScalerOf(context);
    final scaledFontSize = textScaler.scale(fontSize);
    
    return TextStyle(
      fontSize: scaledFontSize.clamp(12.0, 28.0), // Limit font size range
      fontWeight: fontWeight,
      color: color,
      height: isLargeTextScale(context) ? 1.4 : 1.2, // Better line height for large text
    );
  }
  
  /// Build focus-aware widget for better keyboard navigation
  static Widget buildFocusableWidget({
    required BuildContext context,
    required Widget child,
    ValueChanged<bool>? onFocusChange,
    bool autofocus = false,
  }) {
    if (isMobile(context)) {
      return child; // Mobile doesn't typically use keyboard focus
    }
    
    return Focus(
      autofocus: autofocus,
      onFocusChange: onFocusChange,
      child: child,
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
  
  // Accessibility convenience methods
  bool get isLargeTextScale => ResponsiveService.isLargeTextScale(this);
  double get contrastRatio => ResponsiveService.getContrastRatio(this);
}