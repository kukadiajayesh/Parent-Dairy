import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Type scale from section "03 — Type scale" of the style guide, expressed as
/// the Material 3 slots the app actually uses.
abstract final class AppText {
  static const headline = TextStyle(
    fontSize: 25,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    height: 1.2,
  );
  static const titleLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
  );
  static const screenTitle = TextStyle(
    fontSize: 23,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
  );
  static const recordTitle = TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.3);
  static const body = TextStyle(fontSize: 14, height: 1.5);
  static const label = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: .2);
  static const overline = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  );
}

abstract final class AppTheme {
  static const _family = 'Figtree';

  static ThemeData light() => _build(AppTokens.light, Brightness.light);
  static ThemeData dark() => _build(AppTokens.dark, Brightness.dark);

  static ThemeData _build(AppTokens k, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: k.priFill,
      onPrimary: Colors.white,
      primaryContainer: k.priC,
      onPrimaryContainer: k.priInk,
      secondary: k.secFill,
      onSecondary: Colors.white,
      secondaryContainer: k.secC,
      onSecondaryContainer: k.secInk,
      tertiary: k.warn,
      onTertiary: Colors.white,
      tertiaryContainer: k.warnC,
      onTertiaryContainer: k.warnInk,
      error: k.errFill,
      onError: Colors.white,
      errorContainer: k.errC,
      onErrorContainer: k.errInk,
      surface: k.bg,
      onSurface: k.tx,
      surfaceContainerLowest: k.bg,
      surfaceContainerLow: k.surf,
      surfaceContainer: k.surf2,
      surfaceContainerHigh: k.surf3,
      surfaceContainerHighest: k.hov,
      onSurfaceVariant: k.tx3,
      outline: k.bd3,
      outlineVariant: k.bd,
    );

    final base = brightness == Brightness.light
        ? ThemeData.light(useMaterial3: true)
        : ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: k.bg,
      canvasColor: k.bg,
      splashFactory: InkSparkle.splashFactory,
      extensions: <ThemeExtension<dynamic>>[k],
      textTheme: base.textTheme.apply(
        fontFamily: _family,
        bodyColor: k.tx,
        displayColor: k.tx,
      ),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: _family),
      iconTheme: IconThemeData(color: k.tx2),
      dividerTheme: DividerThemeData(color: k.bd, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: k.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: k.tx,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppText.titleLarge.copyWith(fontFamily: _family, color: k.tx),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: k.bg,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: const Color(0x6B1F1B16),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: k.bg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: k.pri,
        selectionColor: k.priC,
        selectionHandleColor: k.pri,
      ),
    );
  }
}
