/*
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * @ Author : CHI-HSIUNG YANG
 * @ File   : main.dart
 */

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'services/db_service.dart';
import 'toolbox/ez_output.dart';
import 'toolbox/language.dart';
import 'toolbox/toolbox.dart';
import './rotues.dart';

final ToolBox toolbox = ToolBox.instance;
final Language language = Language.instance;
final DbService dbService = DbService.instance;

bool _reentry = false;

void main(List<String> args) {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    final bool isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;

    // 1. Initialize Desktop Window Manager
    if (isDesktop) {
      await windowManager.ensureInitialized();
      WindowOptions windowOptions = const WindowOptions(
        size: Size(1280, 800),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      );

      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.setResizable(true);
        await windowManager.show();
        await windowManager.focus();
      });
    }

    if (_reentry) {
      ezOutput("[INFO] Reentry ignored");
      return;
    }

    const SystemUiOverlayStyle systemUiOverlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
    );
    SystemChrome.setSystemUIOverlayStyle(systemUiOverlayStyle);

    _reentry = true;

    // 2. Mobile system style and orientation configuration (desktop does not restrict orientation)
    if (!isDesktop) {
      await ToolBox.redoSystemStyle();
      // Supported orientations: Retain rotation capabilities, individual pages determine orientation dynamically
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    // 3. Configure native platform storage directories
    toolbox.getPlatformSupport(false);
    await toolbox.setDocDir();

    // 4. Internet connectivity diagnostics
    if (await toolbox.getInternetConnect()) {
      ezOutput("[INFO] Connected to the Internet");
    } else {
      ezOutput("[INFO] Not connected to the network");
    }

    // 5. Mobile locale detection
    if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) {
      await toolbox.getLocalInfo();
    }
    language.setLanguage(toolbox.languageFile);
    await language.loadData();

    String strToday = toolbox.getToday();
    ezOutput('[INFO] Today = $strToday');

    String? initialFilePath;
    if (args.isNotEmpty && args.first.toLowerCase().endsWith('.ebf')) {
      initialFilePath = args.first;
    }

    runApp(
      Routes(
        key: const Key('ez_db_routes_root'),
        strInitialFilePath: initialFilePath,
      ),
    );
  }, (Object error, StackTrace stackTrace) {
    ezOutput('[ERROR] Uncaught exception occurred');
    ezOutput('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');
    ezOutput('Error code : $error');
    ezOutput('Stack trace : $stackTrace');
  });
}
