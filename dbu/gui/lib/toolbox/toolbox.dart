/*
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * This source code may not be redistributed without the copyright owner's
 * written consent.
 *
 * @ Author : CHI-HSIUNG YANG
 * @ File   : toolbox.dart
 */

library toolbox;

import 'dart:async';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:devicelocale/devicelocale.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'ez_output.dart';

class ToolBox {
  static final ToolBox _toolbox = ToolBox._internal();
  ToolBox._internal();

  static ToolBox get instance => _toolbox;

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // Member Variables
  String _docDir = '';
  //String _languageCode = 'zh_TW';
  //String _languageFile = 'zh_TW';
  String _languageCode = 'en_US';
  String _languageFile = 'en_US';
  bool _isAndroid = false;
  bool _isIos = false;
  Map<String, dynamic> _deviceData = <String, dynamic>{};
  Map<String, dynamic> get deviceData => _deviceData;

  String get docDir => _docDir;
  String get languageFile => _languageFile;
  bool get isAndroid => _isAndroid;
  bool get isIos => _isIos;

  /// System UI orientation & status bar lock
  static Future<void> redoSystemStyle() async {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
    ));
    ezOutput('[INFO] System UI style updated.');
  }

  /// Initialize application document directory
  Future<void> setDocDir() async {
    try {
      _docDir = (await getApplicationDocumentsDirectory()).path;
      ezOutput('[INFO] Document Directory: $_docDir');
    } catch (e) {
      _docDir = Directory.current.path;
      ezOutput('[INFO] Document Directory fallback: $_docDir');
    }
  }

  /// Internet connection lookup
  Future<bool> getInternetConnect() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }
    } on SocketException catch (_) {
      return false;
    }
    return false;
  }

  /// Detect platform details and hardware matrix
  Future<void> getPlatformSupport([bool showDevice = false]) async {
    final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
    var deviceData = <String, dynamic>{};
    try {
      if (kIsWeb) {
        ezOutput('[INFO] Platform: Web Engine.');
      } else if (Platform.isWindows) {
        ezOutput('[INFO] Platform: Windows Desktop.');
        var windowsInfo = await deviceInfoPlugin.windowsInfo;
        _deviceData = {'computerName': windowsInfo.computerName, 'cores': windowsInfo.numberOfCores};
      } else if (Platform.isMacOS) {
        ezOutput('[INFO] Platform: macOS Desktop.');
      } else if (Platform.isLinux) {
        ezOutput('[INFO] Platform: Linux Engine.');
      } else if (Platform.isAndroid) {
        ezOutput('[INFO] Platform: Android Mobile.');
        _isAndroid = true;
      } else if (Platform.isIOS) {
        ezOutput('[INFO] Platform: iOS Mobile.');
        _isIos = true;
      }
      _deviceData = deviceData;
    } catch (e) {
      ezOutput('[ERROR] Platform detection failed: $e');
    }
  }

  /// Fetch locale information from device
  Future<void> getLocalInfo() async {
    try {
      Locale? myLocale = await Devicelocale.currentAsLocale;
      if (myLocale != null) {
        String countryCode = ('Hant' == myLocale.countryCode) ? 'TW' : (myLocale.countryCode ?? 'TW').toUpperCase();
        _languageCode = myLocale.languageCode;
        _languageFile = '${_languageCode}_$countryCode';
        ezOutput('[INFO] System Locale detected => $_languageFile');
      }
    } catch (e) {
      ezOutput('[ERROR] Locale detection error: $e');
    }
  }

  void setLanguageCode(String code) {
    _languageCode = code;
  }

  // Retrieve today's date formatted according to specific requirements
  String getToday() {
    final DateTime now = DateTime.now();

    if (_languageCode == 'zh_TW') {
      // 1. Chinese month lookup table
      const List<String> lstTwMonths = <String>['一月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '十一月', '十二月'];

      // 2. Chinese day lookup table
      const List<String> lstTwDays = <String>[
        '一日',
        '二日',
        '三日',
        '四日',
        '五日',
        '六日',
        '七日',
        '八日',
        '九日',
        '十日',
        '十一日',
        '十二日',
        '十三日',
        '十四日',
        '十五日',
        '十六日',
        '十七日',
        '十八日',
        '十九日',
        '二十日',
        '二十一日',
        '二十二日',
        '二十三日',
        '二十四日',
        '二十五日',
        '二十六日',
        '二十七日',
        '二十八日',
        '二十九日',
        '三十日',
        '三十一日'
      ];

      // 3. Calculate ROC year (Gregorian year - 1911)
      final int iRocYear = now.year - 1911;

      // 4. Assemble precisely (e.g., "八月二日115年")
      final String strMonth = lstTwMonths[now.month - 1];
      final String strDay = lstTwDays[now.day - 1];
      final String strResult = '$strMonth$strDay$iRocYear年';

      ezOutput('[INFO] Conversion result => $strResult');
      return strResult;
    } else {
      // Output standard English format for non-Chinese locales (enforce en_US to prevent locale pollution)
      return DateFormat('EEE / MMM.d.yyyy', 'en_US').format(now);
    }
  }
}