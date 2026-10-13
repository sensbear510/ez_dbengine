// ignore_for_file: unused_field

/*
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * This source code may not be redistributed without the copyright owner's
 * written consent.
 *
 * @ Author : CHI-HSIUNG YANG
 * @ File   : settings.dart
 */

library toolbox;

class Settings {
  static final Settings _settings = Settings._internal();
  Settings._internal();

  static Settings get instance => _settings;

  // App Metadata
  final String _appName = 'ezDBUtility';
  final String _appVersion = '1.0.0';

  String get appName => _appName;
  String get appVersion => _appVersion;
}
