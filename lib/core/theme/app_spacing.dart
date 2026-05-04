import 'package:flutter/material.dart';

/// Sistema di spaziatura a **griglia 4px** (Forex Terminal Pro).
///
/// | Token | Valore | Uso tipico |
/// |-------|--------|------------|
/// | [pageH] / [pageScroll] | 16px orizzontali | Contenitore esterno pagina (px-4) |
/// | [card] | 16px tutti i lati | Card e widget densi (p-4) |
/// | [inputTouch] | 16h × 12v | Chip, selezione date/coppie, touch target |
/// | [section] / [sectionLg] | 16 / 20 | Spazio verticale tra blocchi (space-y-4 / y-5) |
///
/// **Import consigliato:** `import '.../app_theme.dart';` — [AppTheme] per i colori e
/// [AppSpacing] (re-export da `app_theme.dart`). In alternativa solo `app_spacing.dart`
/// se non servono i token colore.
///
/// Usa [AppSpacing] al posto di numeri magici; mantieni multipli di [grid] salvo
/// eccezioni documentate.
abstract final class AppSpacing {
  AppSpacing._();

  static const double grid = 4;

  static const double s1 = grid;
  static const double s2 = grid * 2;
  static const double s3 = grid * 3;
  static const double s4 = grid * 4;
  static const double s5 = grid * 5;
  static const double s6 = grid * 6;
  static const double s7 = grid * 7;
  static const double s8 = grid * 8;

  /// Laterale pagina (Tailwind `px-4`).
  static const double pageH = s4;

  /// Scroll principale: laterali 16, top 12, bottom 24.
  static const EdgeInsets pageScroll =
      EdgeInsets.fromLTRB(pageH, s3, pageH, s6);

  /// Come [pageScroll] ma bottom 28px (7× griglia).
  static const EdgeInsets pageScrollBottomLoose =
      EdgeInsets.fromLTRB(pageH, s3, pageH, s7);

  /// Schermate auth / form centrati: 16 orizzontale, 24 verticale.
  static const EdgeInsets pageAuth =
      EdgeInsets.symmetric(horizontal: pageH, vertical: s6);

  /// Solo margini orizzontali pagina (es. `ListView.padding`).
  static const EdgeInsets pageHorizontalOnly =
      EdgeInsets.symmetric(horizontal: pageH);

  /// Card sotto app bar: 16 H, 8 V.
  static const EdgeInsets insetCardScreen =
      EdgeInsets.fromLTRB(pageH, s2, pageH, s2);

  /// Padding interno card / pannelli (p-4).
  static const EdgeInsets card = EdgeInsets.all(s4);

  /// Input, chip, controlli selezione (py-3 px-4).
  static const EdgeInsets inputTouch =
      EdgeInsets.symmetric(horizontal: s4, vertical: s3);

  /// Tra sezioni principali (space-y-4).
  static const double section = s4;

  /// Tra sezioni più distanziate (space-y-5).
  static const double sectionLg = s5;

  // --- Widget di gap verticale (const) ---

  static const Widget gapS1 = SizedBox(height: s1);
  static const Widget gapS2 = SizedBox(height: s2);
  static const Widget gapS3 = SizedBox(height: s3);
  static const Widget gapSection = SizedBox(height: section);
  static const Widget gapSectionLg = SizedBox(height: sectionLg);
  static const Widget gapS6 = SizedBox(height: s6);
  static const Widget gapS8 = SizedBox(height: s8);
}
