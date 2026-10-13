/*
 * =================================================================================================
 * 📄 MODULE: Craftsman About Dialog Panel Widget (RWD Adaptive)
 * 📁 PATH: dbu/gui/lib/views/widgets/about_dialog_panel.dart
 * =================================================================================================
 */

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../language.dart';

/// Craftsman style sliding bottom About panel widget
class AboutDialogPanel extends StatelessWidget {
  const AboutDialogPanel({super.key});

  /// Static factory method to display the smooth sliding About panel
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (BuildContext context) => const AboutDialogPanel(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CraftsmanColors craftsmanColors = context.craftsmanColors;
    final Language language = Language.instance;

    return Center(
      child: ConstrainedBox(
        // RWD protection: Constrain max width to 480px on desktop and tablet, dynamically fit screen width on mobile
        constraints: const BoxConstraints(maxWidth: 480.0),
        child: Container(
          key: const Key('ez_db_about_panel_container'),
          decoration: BoxDecoration(
            color: craftsmanColors.m_colorHeaderBg ?? theme.cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16.0)),
            border: Border.all(
              color: craftsmanColors.m_colorWarmAmber ?? theme.colorScheme.primary,
              width: 1.0,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Colors.black54,
                blurRadius: 20.0,
                offset: Offset(0.0, -4.0),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Top Drag Handle Indicator Pill
                Container(
                  width: 36.0,
                  height: 4.0,
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2.0),
                  ),
                ),
                const SizedBox(height: 16.0),

                // App Logo & Header Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.storage_rounded,
                      size: 32.0,
                      color: craftsmanColors.m_colorWarmAmber ?? theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12.0),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'ezDBUtility',
                          style: context.uiBoldStyle.copyWith(
                            fontSize: 18.0,
                            color: craftsmanColors.m_colorWarmAmber ?? theme.colorScheme.primary,
                          ),
                        ),
                        Text(
                          'Visual Database Engine Suite',
                          style: context.monoCaptionStyle,
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16.0),
                Divider(color: craftsmanColors.m_colorBorder ?? theme.dividerColor, height: 1.0),
                const SizedBox(height: 16.0),

                // Detailed System Metadata Information
                _buildInfoRow(context, 'Application Version:', 'v1.0.0 (Build 2026.09)'),
                const SizedBox(height: 8.0),
                _buildInfoRow(context, 'Core Engine:', 'ez_dbengine C-Core Native I/O'),
                const SizedBox(height: 8.0),
                _buildInfoRow(context, 'Storage Protocol:', 'Local / Mounted EBF+EDX+ZBF'),
                const SizedBox(height: 8.0),
                _buildInfoRow(context, 'Copyright:', '© 2026 ezLink.io All rights reserved.'),
                const SizedBox(height: 8.0),
                _buildInfoRow(context, 'Author:', 'CHI-HSIUNG YANG'),

                const SizedBox(height: 24.0),

                // OK Action Button to Dismiss Panel Smoothly
                SizedBox(
                  width: double.infinity,
                  height: 38.0,
                  child: ElevatedButton(
                    key: const Key('ez_db_about_ok_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: craftsmanColors.m_colorCraftsmanBrown ?? theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6.0),
                      ),
                      elevation: 2.0,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      language.getValue('BTN_OK'),
                      style: context.uiBoldStyle.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String strLabel, String strValue) {
    final ThemeData theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          strLabel,
          style: context.uiStyle.copyWith(
            fontSize: 11.0,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        Text(
          strValue,
          style: context.monoStyle.copyWith(
            fontSize: 11.0,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}