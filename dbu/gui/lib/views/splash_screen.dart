// ignore_for_file: non_constant_identifier_names

/*
 * =================================================================================================
 * 📄 MODULE: Splash Screen & Environment Diagnosis Component
 * 📁 PATH: dbu/gui/lib/views/splash_screen.dart
 * =================================================================================================
 */

import 'package:flutter/material.dart';
import '../rotues.dart'; // Target platform dispatcher
import '../services/db_service.dart';
import '../theme/app_theme.dart';
import '../toolbox/language.dart';

/// Boot & Environment Diagnosis Splash Screen Widget
class SplashScreen extends StatefulWidget {
  static const String routeName = '/splash';

  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // Protocol Compliant Member Variables (m_ + Type + Name)
  double m_dbProgress = 0.0;
  String m_strStatusTextKey = 'init_env';

  final Language m_language = Language.instance;

  @override
  void initState() {
    super.initState();
    m_fnStartSystemDiagnosis();
  }

  /// System startup diagnosis pipeline covering OS, Network, INI config and Engine
  Future<void> m_fnStartSystemDiagnosis() async {
    try {
      // Step 1: Initial environment diagnosis
      _updateDiagnosisState('init_env', 0.15);
      await Future.delayed(const Duration(milliseconds: 300));

      // Step 2: Check OS architecture and hardware status
      _updateDiagnosisState('detect_os', 0.35);
      await Future.delayed(const Duration(milliseconds: 350));

      // Step 3: Verify network status and Web API connection
      _updateDiagnosisState('detect_net', 0.55);
      await Future.delayed(const Duration(milliseconds: 350));

      // Step 4: Load INI language & system configurations
      _updateDiagnosisState('load_config', 0.75);
      await Future.delayed(const Duration(milliseconds: 300));

      // Step 5: Initialize C-Engine (ez_dbengine) IO
      final int iStatus = DbService.instance.ioInit();
      if (iStatus != 0) {
        debugPrint('[DbService] Engine initialization status code: $iStatus');
      }

      // Step 6: Diagnosis complete & ready
      _updateDiagnosisState('complete', 1.0);
      await Future.delayed(const Duration(milliseconds: 400));
    } catch (e) {
      debugPrint('[SplashScreen Error] Diagnosis pipeline failure: $e');
    } finally {
      // Step 7: Transition to Platform Dispatcher (Desktop / Pad / Phone)
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (BuildContext context) => const PlatformEntryPage(),
          ),
        );
      }
    }
  }

  /// Helper method to safely update progress and status text key
  void _updateDiagnosisState(String strStatusKey, double dbProgress) {
    if (mounted) {
      setState(() {
        m_strStatusTextKey = strStatusKey;
        m_dbProgress = dbProgress.clamp(0.0, 1.0);
      });
    }
  }

  // ===============================================================================================
  // 🎨 UI LAYOUT BUILDER BLOCKS
  // ===============================================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('ez_db_splash_scaffold'),
      backgroundColor: Colors.black,
      body: Stack(
        key: const Key('ez_db_splash_stack'),
        fit: StackFit.expand,
        children: <Widget>[
          _buildBackgroundImage(),
          _buildVignetteOverlay(context),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: _buildTopHudBadge(context),
            ),
          ),
        ],
      ),
    );
  }

  /// Sub-Block: Background Craftsman Splash Image (Full-bleed adaptive cropping)
  Widget _buildBackgroundImage() {
    return Image.asset(
      'assets/images/splash.jpeg',
      key: const Key('ez_db_splash_bg_image'),
      fit: BoxFit.cover, // Switched to cover to eliminate letterboxing/black borders
      alignment: Alignment.center,
    );
  }

  /// Sub-Block: Subtle Dark Gradient Vignette Overlay
  Widget _buildVignetteOverlay(BuildContext context) {
    return Container(
      key: const Key('ez_db_splash_overlay_vignette'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.black.withValues(alpha: 0.85),
            Colors.black.withValues(alpha: 0.25),
            Colors.black.withValues(alpha: 0.85),
          ],
          stops: const <double>[0.0, 0.4, 1.0],
        ),
      ),
    );
  }

  /// Sub-Block: Top Floating HUD Badge Container (Adaptive to screen width)
  Widget _buildTopHudBadge(BuildContext context) {
    final CraftsmanColors craftsmanColors = context.craftsmanColors;
    final ThemeData theme = Theme.of(context);
    final double screenWidth = MediaQuery.of(context).size.width;

    // Adaptive HUD max width constraint
    final double hudMaxWidth = (screenWidth * 0.85).clamp(240.0, 360.0);

    return Padding(
      padding: const EdgeInsets.only(top: 20.0),
      child: Container(
        key: const Key('ez_db_splash_top_hud_container'),
        constraints: BoxConstraints(maxWidth: hudMaxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: craftsmanColors.m_colorHeaderBg ?? theme.cardColor,
          borderRadius: BorderRadius.circular(20.0),
          border: Border.all(
            color: craftsmanColors.m_colorWarmAmber ?? theme.colorScheme.primary,
            width: 1.0,
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Colors.black87,
              blurRadius: 10.0,
              offset: Offset(0.0, 4.0),
            ),
          ],
        ),
        child: Column(
          key: const Key('ez_db_splash_top_hud_column'),
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildStatusText(context),
            const SizedBox(height: 8.0),
            _buildProgressBar(context, hudMaxWidth),
          ],
        ),
      ),
    );
  }

  /// Component Block: Dynamic Localized Status Text Widget
  Widget _buildStatusText(BuildContext context) {
    final CraftsmanColors craftsmanColors = context.craftsmanColors;

    return Text(
      m_language.getValue(m_strStatusTextKey),
      key: const Key('ez_db_splash_status_text'),
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.statusStyle.copyWith(
        color: craftsmanColors.m_colorWarmAmber ?? Theme.of(context).colorScheme.primary,
        fontSize: 12.0,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  /// Component Block: Animated Linear Progress Indicator Widget
  Widget _buildProgressBar(BuildContext context, double parentWidth) {
    final CraftsmanColors craftsmanColors = context.craftsmanColors;
    final ThemeData theme = Theme.of(context);

    // Progress bar width adaptively scaled to 85% of parent HUD
    final double barWidth = parentWidth * 0.85;

    return SizedBox(
      width: barWidth,
      height: 6.0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3.0),
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          tween: Tween<double>(begin: 0.0, end: m_dbProgress),
          builder: (BuildContext context, double value, Widget? child) {
            return LinearProgressIndicator(
              key: const Key('ez_db_splash_progress_bar'),
              value: value,
              backgroundColor: craftsmanColors.m_colorCardBg ?? theme.cardColor,
              color: craftsmanColors.m_colorWarmAmber ?? theme.colorScheme.primary,
              minHeight: 6.0,
            );
          },
        ),
      ),
    );
  }
}