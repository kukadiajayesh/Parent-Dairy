import 'package:flutter/material.dart';

/// Design tokens transcribed 1:1 from `Parent Academic Diary.dc.html`
/// (`:root` for light, `[data-theme="dark"]` for dark).
///
/// Exposed through [Theme] as a [ThemeExtension] so every screen reads the
/// same values the design does, and both themes stay in lockstep.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.page,
    required this.bg,
    required this.surf,
    required this.surf2,
    required this.surf3,
    required this.hov,
    required this.hov2,
    required this.skel,
    required this.bd,
    required this.bd2,
    required this.bd3,
    required this.bd4,
    required this.bd5,
    required this.tx,
    required this.tx2,
    required this.tx3,
    required this.tx4,
    required this.tx5,
    required this.tx6,
    required this.pri,
    required this.priFill,
    required this.priFillH,
    required this.priC,
    required this.priCH,
    required this.priInk,
    required this.priInk2,
    required this.priBd,
    required this.sec,
    required this.secFill,
    required this.secFillH,
    required this.secC,
    required this.secCH,
    required this.secInk,
    required this.secInk2,
    required this.err,
    required this.errFill,
    required this.errFillH,
    required this.errC,
    required this.errCH,
    required this.errInk,
    required this.errInk2,
    required this.warn,
    required this.warnC,
    required this.warnInk,
    required this.warnInk2,
    required this.subMathC,
    required this.subMathInk,
    required this.subEngC,
    required this.subEngInk,
    required this.subSciC,
    required this.subSciInk,
    required this.subHinC,
    required this.subHinInk,
    required this.subComC,
    required this.subComInk,
    required this.subArtC,
    required this.subArtInk,
    required this.subOthC,
    required this.subOthInk,
  });

  // Surfaces
  final Color page, bg, surf, surf2, surf3, hov, hov2, skel;
  // Borders
  final Color bd, bd2, bd3, bd4, bd5;
  // Text
  final Color tx, tx2, tx3, tx4, tx5, tx6;
  // Primary
  final Color pri, priFill, priFillH, priC, priCH, priInk, priInk2, priBd;
  // Secondary
  final Color sec, secFill, secFillH, secC, secCH, secInk, secInk2;
  // Error
  final Color err, errFill, errFillH, errC, errCH, errInk, errInk2;
  // Warning
  final Color warn, warnC, warnInk, warnInk2;
  // Subject hues
  final Color subMathC, subMathInk;
  final Color subEngC, subEngInk;
  final Color subSciC, subSciInk;
  final Color subHinC, subHinInk;
  final Color subComC, subComInk;
  final Color subArtC, subArtInk;
  final Color subOthC, subOthInk;

  static const AppTokens light = AppTokens(
    page: Color(0xFFEFEAE3),
    bg: Color(0xFFFBF8F4),
    surf: Color(0xFFFFFFFF),
    surf2: Color(0xFFF3EDE5),
    surf3: Color(0xFFF1EAE1),
    hov: Color(0xFFEAE1D5),
    hov2: Color(0xFFF7F2EA),
    skel: Color(0xFFE5DCCF),
    bd: Color(0xFFEDE5DA),
    bd2: Color(0xFFE7DFD5),
    bd3: Color(0xFFE0D7CA),
    bd4: Color(0xFFDCD2C4),
    bd5: Color(0xFFCFC5B8),
    tx: Color(0xFF1F1B16),
    tx2: Color(0xFF4A423A),
    tx3: Color(0xFF6F6558),
    tx4: Color(0xFF8A7E70),
    tx5: Color(0xFFA79B8C),
    tx6: Color(0xFF9A8F80),
    pri: Color(0xFF3F4C8C),
    priFill: Color(0xFF3F4C8C),
    priFillH: Color(0xFF354277),
    priC: Color(0xFFDDE1F5),
    priCH: Color(0xFFD1D6F0),
    priInk: Color(0xFF2A3468),
    priInk2: Color(0xFF4A5490),
    priBd: Color(0xFFC9CFEA),
    sec: Color(0xFF3C7C72),
    secFill: Color(0xFF3C7C72),
    secFillH: Color(0xFF346B62),
    secC: Color(0xFFD4E5E0),
    secCH: Color(0xFFC7DCD6),
    secInk: Color(0xFF1E3F39),
    secInk2: Color(0xFF2E5B52),
    err: Color(0xFF8C3B32),
    errFill: Color(0xFF8C3B32),
    errFillH: Color(0xFF76302A),
    errC: Color(0xFFF7E7E4),
    errCH: Color(0xFFF1DAD5),
    errInk: Color(0xFF5E2A23),
    errInk2: Color(0xFF7A3A31),
    warn: Color(0xFFA98035),
    warnC: Color(0xFFF3E7CF),
    warnInk: Color(0xFF6B4E17),
    warnInk2: Color(0xFF7A5C25),
    subMathC: Color(0xFFE4E7F7),
    subMathInk: Color(0xFF4759A8),
    subEngC: Color(0xFFF4E3DD),
    subEngInk: Color(0xFF6E3A2B),
    subSciC: Color(0xFFD9E8E1),
    subSciInk: Color(0xFF245040),
    subHinC: Color(0xFFE7E0F1),
    subHinInk: Color(0xFF443767),
    subComC: Color(0xFFDCE6EE),
    subComInk: Color(0xFF2B4C60),
    subArtC: Color(0xFFEFE1E6),
    subArtInk: Color(0xFF63333F),
    subOthC: Color(0xFFE5E2DC),
    subOthInk: Color(0xFF494437),
  );

  static const AppTokens dark = AppTokens(
    page: Color(0xFF0E0D0B),
    bg: Color(0xFF141310),
    surf: Color(0xFF1F1C19),
    surf2: Color(0xFF26231F),
    surf3: Color(0xFF2A2723),
    hov: Color(0xFF302C27),
    hov2: Color(0xFF26231F),
    skel: Color(0xFF2E2A25),
    bd: Color(0xFF33302B),
    bd2: Color(0xFF33302B),
    bd3: Color(0xFF3B372F),
    bd4: Color(0xFF3B372F),
    bd5: Color(0xFF4A443C),
    tx: Color(0xFFF5F0E9),
    tx2: Color(0xFFDCD4C9),
    tx3: Color(0xFFB3AA9E),
    tx4: Color(0xFF9C948A),
    tx5: Color(0xFF8A8177),
    tx6: Color(0xFF8A8177),
    pri: Color(0xFFA3AEE6),
    priFill: Color(0xFF4E5CA8),
    priFillH: Color(0xFF5C6ABA),
    priC: Color(0xFF2E3868),
    priCH: Color(0xFF3A457C),
    priInk: Color(0xFFC6CDF0),
    priInk2: Color(0xFFAAB3E0),
    priBd: Color(0xFF4A5590),
    sec: Color(0xFF7FC4B4),
    secFill: Color(0xFF35786D),
    secFillH: Color(0xFF40897C),
    secC: Color(0xFF23453E),
    secCH: Color(0xFF2C554C),
    secInk: Color(0xFFA5CFC3),
    secInk2: Color(0xFF8FBDB2),
    err: Color(0xFFE8A79F),
    errFill: Color(0xFFA24A3F),
    errFillH: Color(0xFFB4574A),
    errC: Color(0xFF3A2320),
    errCH: Color(0xFF482C27),
    errInk: Color(0xFFF0C4BD),
    errInk2: Color(0xFFDCA79E),
    warn: Color(0xFFD2A85A),
    warnC: Color(0xFF3A2F1B),
    warnInk: Color(0xFFE5C98A),
    warnInk2: Color(0xFFCBAE79),
    subMathC: Color(0xFF262E52),
    subMathInk: Color(0xFF9DA9E4),
    subEngC: Color(0xFF3B2721),
    subEngInk: Color(0xFFE0AC9B),
    subSciC: Color(0xFF1E3F37),
    subSciInk: Color(0xFF9FCBBB),
    subHinC: Color(0xFF2C2440),
    subHinInk: Color(0xFFBDAFDF),
    subComC: Color(0xFF1F3340),
    subComInk: Color(0xFF9EC3D6),
    subArtC: Color(0xFF3A2830),
    subArtInk: Color(0xFFDFAEBC),
    subOthC: Color(0xFF2C2A25),
    subOthInk: Color(0xFFC3BCAE),
  );

  @override
  AppTokens copyWith() => this;

  /// The two token sets are discrete palettes, not a continuum: interpolating
  /// them would produce muddy in-between colours, so we snap at the midpoint.
  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return t < 0.5 ? this : other;
  }
}

extension AppTokensX on BuildContext {
  AppTokens get t => Theme.of(this).extension<AppTokens>()!;
}
