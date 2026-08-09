import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design tokens for SmartExpense.
///
/// Everything visual funnels through here so light and dark stay in sync and no
/// screen has to invent its own colours, radii or spacing.
class AppTokens {
  const AppTokens._();

  /// Brand seed. Every colour role is derived from this.
  static const Color seed = Color(0xFF2A9D8F);

  // Corner radii.
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 18;
  static const double radiusXl = 24;
  static const double radiusPill = 999;

  // Spacing.
  static const double gapXs = 4;
  static const double gapSm = 8;
  static const double gapMd = 12;
  static const double gapLg = 16;
  static const double gapXl = 24;

  /// Horizontal page gutter used by every screen.
  static const double pageGutter = 16;

  /// Height of the custom bottom navigation bar (excluding the system inset).
  static const double navBarHeight = 64;

  /// Extra room the docked FAB needs so it never covers list content.
  static const double fabClearance = 28;

  /// Standard duration for micro-interactions.
  static const Duration motionFast = Duration(milliseconds: 180);
  static const Duration motionMedium = Duration(milliseconds: 300);
}

/// Semantic colour roles layered on top of the generated [ColorScheme].
///
/// M3 gives us a tonal ramp; these getters name the tones we actually use so a
/// card is never painted with the same colour as the page behind it.
extension AppColorRoles on ColorScheme {
  bool get _isLight => brightness == Brightness.light;

  /// Page background.
  Color get appBackground => _isLight ? surfaceContainerLow : surface;

  /// Default raised container (cards, tiles, sheets).
  Color get appCard => _isLight ? surfaceContainerLowest : surfaceContainerHigh;

  /// A second, slightly recessed container for content inside a card.
  Color get appCardMuted => _isLight ? surfaceContainer : surfaceContainerHighest;

  /// Hairline border for cards and tiles.
  Color get appBorder => outlineVariant;

  /// Fill for the big balance / profile hero cards.
  ///
  /// M3 makes `primary` a pale pastel in dark mode, so a full-bleed primary
  /// card turns into a glaring slab. Dark mode uses the container roles, which
  /// are the deep tones intended for large fills.
  List<Color> get appHeroGradient => _isLight
      ? [primary, Color.lerp(primary, tertiary, 0.42)!]
      : [
          primaryContainer,
          Color.lerp(primaryContainer, tertiaryContainer, 0.45)!,
        ];

  /// Foreground for anything sitting on [appHeroGradient].
  Color get appOnHero => _isLight ? onPrimary : onPrimaryContainer;

  /// Categorical palette for charts.
  ///
  /// Mid-luminance on purpose: these have to stay legible against both the
  /// near-white light background and the near-black dark one.
  static const List<Color> chartPalette = [
    Color(0xFFE76F51), // warm orange
    Color(0xFF4EA8DE), // blue
    Color(0xFFE9C46A), // amber
    Color(0xFF2A9D8F), // teal
    Color(0xFFEF476F), // pink red
    Color(0xFF9B5DE5), // purple
    Color(0xFF06D6A0), // mint
    Color(0xFFF4A261), // sand
    Color(0xFF64B5F6), // sky
    Color(0xFFFF8FA3), // rose
    Color(0xFF74C365), // green
    Color(0xFFA0A7FF), // periwinkle
  ];

  /// Money going out.
  Color get appExpense => _isLight ? const Color(0xFFD62828) : const Color(0xFFFF6B6B);

  /// Money coming in.
  Color get appIncome => _isLight ? const Color(0xFF1B8A5A) : const Color(0xFF4ADE80);

  /// Warning / "due soon" accent.
  Color get appWarning => _isLight ? const Color(0xFFB45309) : const Color(0xFFFBBF24);

  /// Shadow tuned per brightness — dark themes need almost none.
  Color shadowAt(double opacity) =>
      Colors.black.withValues(alpha: _isLight ? opacity : opacity * 0.6);
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  /// System UI overlay (status bar + gesture bar) matched to the theme.
  static SystemUiOverlayStyle overlayStyle(ColorScheme scheme) {
    final isLight = scheme.brightness == Brightness.light;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
      statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: scheme.appCard,
      systemNavigationBarIconBrightness:
          isLight ? Brightness.dark : Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    );
  }

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppTokens.seed,
      brightness: brightness,
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);

    RoundedRectangleBorder rounded(double radius) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );

    OutlineInputBorder inputBorder(Color color, double width) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          borderSide: BorderSide(color: color, width: width),
        );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.appBackground,
      canvasColor: scheme.appBackground,
      dividerColor: scheme.appBorder,
      splashFactory: InkSparkle.splashFactory,

      textTheme: base.textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.appBackground,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: scheme.onSurface),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: overlayStyle(scheme),
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),

      cardTheme: CardThemeData(
        color: scheme.appCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          side: BorderSide(color: scheme.appBorder),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.appBorder,
        thickness: 1,
        space: 1,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        shape: rounded(AppTokens.radiusMd),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.gapLg,
          vertical: AppTokens.gapXs,
        ),
        minVerticalPadding: AppTokens.gapMd,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 3,
        focusElevation: 4,
        highlightElevation: 6,
      ),

      // Height is intentionally left unset so the bar sizes to its child plus
      // the system gesture inset that BottomAppBar's own SafeArea adds.
      bottomAppBarTheme: BottomAppBarThemeData(
        color: scheme.appCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.appCard,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.appCard,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.appCard,
        showDragHandle: true,
        dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.radiusXl),
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.appCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: rounded(AppTokens.radiusXl),
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.gapXl,
          vertical: AppTokens.gapXl,
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: scheme.appCard,
        surfaceTintColor: Colors.transparent,
        shape: rounded(AppTokens.radiusMd),
        elevation: 3,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.appCardMuted,
        contentPadding: const EdgeInsets.symmetric(
          vertical: AppTokens.gapLg,
          horizontal: AppTokens.gapLg,
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        floatingLabelStyle: TextStyle(color: scheme.primary),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        border: inputBorder(scheme.appBorder, 1),
        enabledBorder: inputBorder(scheme.appBorder, 1),
        focusedBorder: inputBorder(scheme.primary, 1.6),
        errorBorder: inputBorder(scheme.error, 1),
        focusedErrorBorder: inputBorder(scheme.error, 1.6),
        errorMaxLines: 2,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
          elevation: 0,
          minimumSize: const Size(64, 48),
          shape: rounded(AppTokens.radiusMd),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: rounded(AppTokens.radiusMd),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(64, 48),
          side: BorderSide(color: scheme.outline),
          shape: rounded(AppTokens.radiusMd),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(48, 44),
          shape: rounded(AppTokens.radiusSm),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          minimumSize: const Size(44, 44),
        ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.primary,
          selectedForegroundColor: scheme.onPrimary,
          foregroundColor: scheme.onSurfaceVariant,
          side: BorderSide(color: scheme.outline),
          shape: rounded(AppTokens.radiusMd),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.appCardMuted,
        selectedColor: scheme.primary.withValues(alpha: 0.16),
        secondarySelectedColor: scheme.primary.withValues(alpha: 0.16),
        side: BorderSide(color: scheme.appBorder),
        shape: rounded(AppTokens.radiusPill),
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.gapSm),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.onPrimary;
          return scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return scheme.outline;
        }),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.appCardMuted,
        circularTrackColor: Colors.transparent,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(
          color: scheme.onInverseSurface,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: scheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.all(AppTokens.gapLg),
        shape: rounded(AppTokens.radiusMd),
        elevation: 2,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
        textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }
}
