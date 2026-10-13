/*
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * @ Author : CHI-HSIUNG YANG
 * @ File   : routes.dart
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'toolbox/language.dart';
import 'toolbox/toolbox.dart';

// Three core responsive view form factors
import 'views/desktop/desktop_main_page.dart';
import 'views/mobile/phone_main_page.dart';
import 'views/tablet/pad_main_page.dart';
import 'views/splash_screen.dart';

final ToolBox toolbox = ToolBox.instance;
final Language language = Language.instance;

/// Top-level platform routing entry point
class PlatformEntryPage extends StatelessWidget {
  final String? strInitialFilePath;
  const PlatformEntryPage({super.key, this.strInitialFilePath});

  @override
  Widget build(BuildContext context) {
    // 1. Native desktop platforms (Windows / Linux / macOS)
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return DesktopMainPage(
        key: const Key('ez_db_desktop_main'),
        strInitialFilePath: strInitialFilePath,
      );
    }

    // 2. Mobile and tablet devices (Android / iOS)
    // Use 600dp shortest side as the breakpoint between Phone and Pad
    final double shortestSide = MediaQuery.of(context).size.shortestSide;
    final bool isPad = shortestSide >= 600;

    if (isPad) {
      return PadMainPage(
        key: const Key('ez_db_pad_main'),
        strInitialFilePath: strInitialFilePath,
      );
    }

    return PhoneMainPage(
      key: const Key('ez_db_phone_main'),
      strInitialFilePath: strInitialFilePath,
    );
  }
}

/// Global Route Table
final Map<String, WidgetBuilder> _routes = <String, WidgetBuilder>{
  SplashScreen.routeName: (BuildContext context) =>
      const SplashScreen(key: Key('ez_db_splash_screen')),
  '/workbench': (BuildContext context) =>
      const PlatformEntryPage(),
};

class Routes extends StatelessWidget {
  final String? strInitialFilePath;
  const Routes({
    super.key,
    this.strInitialFilePath,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      key: const Key('ez_db_app_material'),
      navigatorKey: toolbox.navigatorKey,
      title: language.getValue('TITLE'),
      debugShowCheckedModeBanner: false,

      // Apply unified theme color palette and design tokens across all platforms
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,

      initialRoute: SplashScreen.routeName,
      routes: _routes,
    );
  }
}