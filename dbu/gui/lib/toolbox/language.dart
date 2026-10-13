/*
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * This source code may not be redistributed without the copyright owner's
 * written consent.
 *
 * @ Author : CHI-HSIUNG YANG
 * @ File   : language.dart
 */

library toolbox;

import 'dart:convert';
import 'package:flutter/services.dart';
import 'ez_output.dart';

class Language {
  static final Language _language = Language._internal();
  Language._internal();

  static Language get instance => _language;

  Map<String, dynamic>? data;
  String _code = 'zh_TW';

  /// Set target language code (e.g., 'zh_TW', 'en_US')
  void setLanguage(String code) {
    _code = (code.length != 5) ? "en_US" : code;
    ezOutput('[INFO] Current language setting: $_code');
  }

  String getLanguage() {
    return _code;
  }

  bool support() {
    if (null == data) return false;
    return (data!.isNotEmpty);
  }

  /// Check whether specified language file exists in rootBundle
  Future<bool> existsLanguage(String path) async {
    try {
      String dataResult = await rootBundle.loadString(path);
      return dataResult.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Load localized JSON dictionary file from assets/language/
  Future<bool> loadData() async {
    if (null != data) {
      ezOutput('[INFO] Lingering language data detected, clearing first');
      data!.clear();
      data = null;
    }

    // Path aligned with assets/language/<code.json>
    String strFile = 'assets/language/$_code.json';
    ezOutput('[INFO] Localization message file => $strFile');

    if (!await existsLanguage(strFile)) {
      ezOutput('[INFO] Language file does not exist, falling back to English => ($strFile)');
      strFile = 'assets/language/en_US.json';
    }

    try {
      String dataResult = await rootBundle.loadString(strFile);
      data = json.decode(dataResult);
      ezOutput('[INFO] Language data loaded successfully, count => ${data?.length}');
      return (data != null && data!.isNotEmpty);
    } catch (e) {
      ezOutput('[ERROR] Exception occurred while parsing language JSON => $e');
      return false;
    }
  }

  /// Retrieve localized string value by key
  String getValue(String key) {
    if (null == data) {
      ezOutput('[INFO] Language strings have not been loaded! Unable to retrieve string.');
      return key;
    }
    if (!data!.containsKey(key)) {
      ezOutput('[INFO] Key not found in localization string table! => $key');
      return key;
    }
    return data![key].toString();
  }
}
