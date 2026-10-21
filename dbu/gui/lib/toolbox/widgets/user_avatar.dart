// ignore_for_file: non_constant_identifier_names

/*
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * This source code may not be redistributed without the copyright owner's
 * written consent.
 *
 * @ Author : CHI-HSIUNG YANG
 * @ File   : user_avatar.dart
 */

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../string_extensions.dart';

enum AvatarSize {
  small(24.0),
  medium(40.0),
  large(72.0);

  final double m_dbRadius;
  const AvatarSize(this.m_dbRadius);
}

/// Standardized User Avatar Widget with Smooth Scaling, Ratio Protection, and Craftsman Frame
class UserAvatar extends StatelessWidget {
  final String m_strPictUrl;
  final double m_dbRadius;

  const UserAvatar({
    super.key,
    required this.m_strPictUrl,
    this.m_dbRadius = 40.0,
  });

  factory UserAvatar.preset({
    Key? key,
    required String strPictUrl,
    AvatarSize size = AvatarSize.medium,
  }) {
    return UserAvatar(
      key: key,
      m_strPictUrl: strPictUrl,
      m_dbRadius: size.m_dbRadius,
    );
  }

  @override
  Widget build(BuildContext context) {
    final double dbDiameter = m_dbRadius * 2;
    final CraftsmanColors craftsmanColors = context.craftsmanColors;

    Widget buildDefaultAvatar() {
      return Container(
        width: dbDiameter,
        height: dbDiameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: craftsmanColors.m_colorBorder ?? Colors.grey.shade600,
            width: 1.0,
          ),
        ),
        child: ClipOval(
          child: Image.asset(
            'assets/images/notassign.png',
            width: dbDiameter,
            height: dbDiameter,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
        ),
      );
    }

    final String strFullUrl = m_strPictUrl.toAbsoluteUrl();
    if (strFullUrl.isEmpty) {
      return buildDefaultAvatar();
    }

    return Container(
      width: dbDiameter,
      height: dbDiameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: craftsmanColors.m_colorWarmAmber ?? Colors.amber.shade700,
          width: 1.0,
        ),
      ),
      child: CachedNetworkImage(
        imageUrl: strFullUrl,
        width: dbDiameter,
        height: dbDiameter,
        imageBuilder: (BuildContext context, ImageProvider imageProvider) {
          return ClipOval(
            child: Image(
              image: imageProvider,
              width: dbDiameter,
              height: dbDiameter,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
            ),
          );
        },
        placeholder: (BuildContext context, String url) => buildDefaultAvatar(),
        errorWidget: (BuildContext context, String url, dynamic error) => buildDefaultAvatar(),
      ),
    );
  }
}
