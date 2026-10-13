// ignore_for_file: non_constant_identifier_names

/*
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * This source code may not be redistributed without the copyright owner's
 * written consent.
 *
 * @ Author : CHI-HSIUNG YANG
 * @ File   : ez_notification.dart
 */

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Centralized System Notification & Floating Overlay Utility
class EzNotification {
  /// Displays a full-width floating top panel notification with smooth slide-down animation
  static void showTopPanel(
    BuildContext context, {
    required String title,
    String? message,
    IconData icon = Icons.info_outline_rounded,
    Color? accentColor,
    Duration duration = const Duration(seconds: 3),
  }) {
    final OverlayState overlayState = Overlay.of(context);

    final ThemeData theme = Theme.of(context);
    final CraftsmanColors craftsmanColors = context.craftsmanColors;

    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (BuildContext ctx) {
        return _TopPanelWidget(
          title: title,
          message: message,
          icon: icon,
          accentColor: accentColor ?? theme.colorScheme.primary,
          theme: theme,
          craftsmanColors: craftsmanColors,
          duration: duration,
          onDismissed: () {
            if (overlayEntry.mounted) {
              overlayEntry.remove();
            }
          },
        );
      },
    );

    overlayState.insert(overlayEntry);
  }
}

/// Internal animated widget for top panel banner
class _TopPanelWidget extends StatefulWidget {
  final String title;
  final String? message;
  final IconData icon;
  final Color accentColor;
  final ThemeData theme;
  final CraftsmanColors craftsmanColors;
  final Duration duration;
  final VoidCallback onDismissed;

  const _TopPanelWidget({
    required this.title,
    this.message,
    required this.icon,
    required this.accentColor,
    required this.theme,
    required this.craftsmanColors,
    required this.duration,
    required this.onDismissed,
  });

  @override
  State<_TopPanelWidget> createState() => _TopPanelWidgetState();
}

class _TopPanelWidgetState extends State<_TopPanelWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _controller.forward();

    Future<void>.delayed(widget.duration, () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  void _dismiss() async {
    await _controller.reverse();
    if (mounted) {
      widget.onDismissed();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double topSafeArea = MediaQuery.of(context).padding.top;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _offsetAnimation,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: topSafeArea + 8.0,
              bottom: 12.0,
              left: 16.0,
              right: 16.0,
            ),
            decoration: BoxDecoration(
              color: widget.craftsmanColors.m_colorHeaderBg ?? widget.theme.cardColor,
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 8.0,
                  offset: Offset(0, 4),
                ),
              ],
              border: Border(
                bottom: BorderSide(
                  color: widget.accentColor,
                  width: 2.0,
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  widget.icon,
                  size: 22.0,
                  color: widget.accentColor,
                ),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.title,
                        style: TextStyle(
                          color: widget.theme.colorScheme.onSurface,
                          fontSize: 13.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.message != null && widget.message!.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2.0),
                        Text(
                          widget.message!,
                          style: TextStyle(
                            color: widget.theme.colorScheme.onSurface.withValues(alpha: 0.75),
                            fontSize: 11.0,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18.0,
                    color: widget.theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  onPressed: _dismiss,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
