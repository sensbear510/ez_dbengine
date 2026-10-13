// ignore_for_file: non_constant_identifier_names

/*
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * This source code may not be redistributed without the copyright owner's
 * written consent.
 *
 * @ Author : CHI-HSIUNG YANG
 * @ File   : app_theme.dart
 */

import 'package:flutter/material.dart';

/// ThemeExtension encapsulating Craftsman Precision custom color palette
class CraftsmanColors extends ThemeExtension<CraftsmanColors> {
  final Color? m_colorSidebarBg;
  final Color? m_colorHeaderBg;
  final Color? m_colorCardBg;
  final Color? m_colorCardActiveBg;
  final Color? m_colorBorder;
  final Color? m_colorWarmAmber;
  final Color? m_colorCraftsmanBrown;
  final Color? m_colorZapRed;
  final Color? m_colorInSync;

  const CraftsmanColors({
    this.m_colorSidebarBg,
    this.m_colorHeaderBg,
    this.m_colorCardBg,
    this.m_colorCardActiveBg,
    this.m_colorBorder,
    this.m_colorWarmAmber,
    this.m_colorCraftsmanBrown,
    this.m_colorZapRed,
    this.m_colorInSync,
  });

  @override
  CraftsmanColors copyWith({
    Color? m_colorSidebarBg,
    Color? m_colorHeaderBg,
    Color? m_colorCardBg,
    Color? m_colorCardActiveBg,
    Color? m_colorBorder,
    Color? m_colorWarmAmber,
    Color? m_colorCraftsmanBrown,
    Color? m_colorZapRed,
    Color? m_colorInSync,
  }) {
    return CraftsmanColors(
      m_colorSidebarBg: m_colorSidebarBg ?? this.m_colorSidebarBg,
      m_colorHeaderBg: m_colorHeaderBg ?? this.m_colorHeaderBg,
      m_colorCardBg: m_colorCardBg ?? this.m_colorCardBg,
      m_colorCardActiveBg: m_colorCardActiveBg ?? this.m_colorCardActiveBg,
      m_colorBorder: m_colorBorder ?? this.m_colorBorder,
      m_colorWarmAmber: m_colorWarmAmber ?? this.m_colorWarmAmber,
      m_colorCraftsmanBrown: m_colorCraftsmanBrown ?? this.m_colorCraftsmanBrown,
      m_colorZapRed: m_colorZapRed ?? this.m_colorZapRed,
      m_colorInSync: m_colorInSync ?? this.m_colorInSync,
    );
  }

  @override
  CraftsmanColors lerp(ThemeExtension<CraftsmanColors>? other, double t) {
    if (other is! CraftsmanColors) return this;
    return CraftsmanColors(
      m_colorSidebarBg: Color.lerp(m_colorSidebarBg, other.m_colorSidebarBg, t),
      m_colorHeaderBg: Color.lerp(m_colorHeaderBg, other.m_colorHeaderBg, t),
      m_colorCardBg: Color.lerp(m_colorCardBg, other.m_colorCardBg, t),
      m_colorCardActiveBg: Color.lerp(m_colorCardActiveBg, other.m_colorCardActiveBg, t),
      m_colorBorder: Color.lerp(m_colorBorder, other.m_colorBorder, t),
      m_colorWarmAmber: Color.lerp(m_colorWarmAmber, other.m_colorWarmAmber, t),
      m_colorCraftsmanBrown: Color.lerp(m_colorCraftsmanBrown, other.m_colorCraftsmanBrown, t),
      m_colorZapRed: Color.lerp(m_colorZapRed, other.m_colorZapRed, t),
      m_colorInSync: Color.lerp(m_colorInSync, other.m_colorInSync, t),
    );
  }

  static const CraftsmanColors light = CraftsmanColors(
    m_colorSidebarBg: Color(0xFFF4F0E8),
    m_colorHeaderBg: Color(0xFFEAE3D5),
    m_colorCardBg: Color(0xFFDDD6C7),
    m_colorCardActiveBg: Color(0xFFF8F5EE),
    m_colorBorder: Color(0xFFCFC6B5),
    m_colorWarmAmber: Color(0xFFB5771A),
    m_colorCraftsmanBrown: Color(0xFF9E6514),
    m_colorZapRed: Color(0xFFD9383A),
    m_colorInSync: Color(0xFF2E7D32),
  );

  static const CraftsmanColors dark = CraftsmanColors(
    m_colorSidebarBg: Color(0xFF1E1E1E),
    m_colorHeaderBg: Color(0xFF252526),
    m_colorCardBg: Color(0xFF2D2D2D),
    m_colorCardActiveBg: Color(0xFF3E3E42),
    m_colorBorder: Color(0xFF3F3F46),
    m_colorWarmAmber: Color(0xFFE5A93C),
    m_colorCraftsmanBrown: Color(0xFFC28628),
    m_colorZapRed: Color(0xFFF44336),
    m_colorInSync: Color(0xFF4CAF50),
  );
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: const Color(0xFFB5771A),
      scaffoldBackgroundColor: const Color(0xFFFAF8F3),
      cardColor: const Color(0xFFF3EFE6),
      dividerColor: const Color(0xFFCFC6B5),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFFB5771A),
        surface: Color(0xFFF3EFE6),
        onSurface: Color(0xFF2A2825),
      ),
      extensions: const <ThemeExtension<dynamic>>[
        CraftsmanColors.light,
      ],
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: const Color(0xFFE5A93C),
      scaffoldBackgroundColor: const Color(0xFF181818),
      cardColor: const Color(0xFF252526),
      dividerColor: const Color(0xFF3F3F46),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFE5A93C),
        surface: Color(0xFF252526),
        onSurface: Color(0xFFE1E1E1),
      ),
      extensions: const <ThemeExtension<dynamic>>[
        CraftsmanColors.dark,
      ],
    );
  }
}

/// DBU Dedicated Typography Extension
extension DbuTypography on ThemeData {
  /// Consolas 11px standard monospace style (DataGrid Cell / StatusBar / Path)
  TextStyle get monoStyle => TextStyle(
        fontFamily: 'Consolas',
        fontSize: 11.0,
        color: colorScheme.onSurface,
      );

  /// Consolas 11px bold monospace style (Header # *, RecNo, Mode Focus)
  TextStyle get monoBoldStyle => monoStyle.copyWith(fontWeight: FontWeight.bold);

  /// Consolas 10px micro monospace style (EDX Key Expression)
  TextStyle get monoCaptionStyle => TextStyle(
        fontFamily: 'Consolas',
        fontSize: 10.0,
        color: colorScheme.onSurface.withValues(alpha: 0.7),
      );

  /// 12px standard UI control text (MenuBar, PopupMenu, TextFields)
  TextStyle get uiStyle => TextStyle(
        fontSize: 12.0,
        color: colorScheme.onSurface,
      );

  /// 12px bold UI control text
  TextStyle get uiBoldStyle => uiStyle.copyWith(fontWeight: FontWeight.bold);

  /// 10px / 11px small badge and status text
  TextStyle get statusStyle => TextStyle(
        fontFamily: 'Consolas',
        fontSize: 11.0,
        fontWeight: FontWeight.w500,
        color: colorScheme.onSurfaceVariant,
      );
}

/// BuildContext Helper Extension for direct theme color and typography access
extension DbuThemeContext on BuildContext {
  ThemeData get theme => Theme.of(this);
  CraftsmanColors get craftsmanColors => theme.extension<CraftsmanColors>() ?? CraftsmanColors.light;

  TextStyle get monoStyle => theme.monoStyle;
  TextStyle get monoBoldStyle => theme.monoBoldStyle;
  TextStyle get monoCaptionStyle => theme.monoCaptionStyle;
  TextStyle get uiStyle => theme.uiStyle;
  TextStyle get uiBoldStyle => theme.uiBoldStyle;
  TextStyle get statusStyle => theme.statusStyle;
}
