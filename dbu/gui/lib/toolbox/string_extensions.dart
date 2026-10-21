/*
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * This source code may not be redistributed without the copyright owner's
 * written consent.
 *
 * @ Author : CHI-HSIUNG YANG
 * @ File   : string_extensions.dart
 */

library toolbox;

import 'language.dart';

/// String Extension providing handy validation and URL resolving utilities
extension StringUrlResolver on String {
  /// Validates whether the current string is a valid email format
  bool get isEmail {
    if (isEmpty) return false;
    final RegExp emailRegExp = RegExp(
      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+",
    );
    return emailRegExp.hasMatch(this);
  }

  /// Automatically completes relative paths from .ebf database into full HTTP URLs
  String toAbsoluteUrl({String? strHostUrl}) {
    if (isEmpty) return '';

    // If already a full URL, return directly
    if (startsWith('http://') || startsWith('https://')) {
      return this;
    }

    // Resolve base host URL from Language dictionary or parameter
    String strBase = strHostUrl ?? Language.instance.getValue('EZLINKHOST');
    if (strBase.isEmpty) {
      strBase = 'https://ezdbutility.ezlink.io';
    }

    // Trim slashes to prevent double slashes (e.g., http://host//path)
    if (strBase.endsWith('/') && startsWith('/')) {
      return '$strBase${substring(1)}';
    } else if (!strBase.endsWith('/') && !startsWith('/')) {
      return '$strBase/$this';
    }

    return '$strBase$this';
  }
}
