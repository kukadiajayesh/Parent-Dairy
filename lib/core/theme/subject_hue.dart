import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// The eight subject hues from the style guide ("02 — Subject tags").
/// One fixed hue per subject: a dot in dense lists, a filled chip on cards.
enum SubjectHue {
  indigo('Indigo', Color(0xFF4759A8)),
  terracotta('Terracotta', Color(0xFFB0654F)),
  green('Green', Color(0xFF3E8168)),
  ochre('Ochre', null), // follows the warning token in both themes
  violet('Violet', Color(0xFF7361A5)),
  steel('Steel', Color(0xFF4C7793)),
  rose('Rose', Color(0xFF9C5A72)),
  stone('Stone', Color(0xFF7A7466));

  const SubjectHue(this.label, this._dot);

  final String label;
  final Color? _dot;

  Color dot(AppTokens k) => _dot ?? k.warn;

  Color tint(AppTokens k) => switch (this) {
        SubjectHue.indigo => k.subMathC,
        SubjectHue.terracotta => k.subEngC,
        SubjectHue.green => k.subSciC,
        SubjectHue.ochre => k.warnC,
        SubjectHue.violet => k.subHinC,
        SubjectHue.steel => k.subComC,
        SubjectHue.rose => k.subArtC,
        SubjectHue.stone => k.subOthC,
      };

  Color ink(AppTokens k) => switch (this) {
        SubjectHue.indigo => k.priInk,
        SubjectHue.terracotta => k.subEngInk,
        SubjectHue.green => k.subSciInk,
        SubjectHue.ochre => k.warnInk,
        SubjectHue.violet => k.subHinInk,
        SubjectHue.steel => k.subComInk,
        SubjectHue.rose => k.subArtInk,
        SubjectHue.stone => k.subOthInk,
      };
}
