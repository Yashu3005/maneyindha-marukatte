import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Profile picture with a built-in default. Customers always see the default (their initial on a brand-colour
/// disc); entrepreneurs can replace it with their own photo. The default is also shown while a photo loads and if
/// the image fails, so a missing/broken URL never breaks a screen.
class UserAvatar extends StatelessWidget {
  final String? url;
  final String? name;
  final double radius;
  final Color? backgroundColor;
  final Color? iconColor;
  const UserAvatar({super.key, this.url, this.name, this.radius = 24, this.backgroundColor, this.iconColor});

  /// First letter of the name, or null when there is no usable name yet ("New Member" is the placeholder).
  static String? initialOf(String? name) {
    final n = name?.trim() ?? '';
    if (n.isEmpty || n == 'New Member') return null;
    return String.fromCharCode(n.runes.first).toUpperCase();
  }

  Widget _default() {
    final initial = initialOf(name);
    // Cream on the brand gradient; deep olive when a light backdrop was asked for.
    final fg = iconColor ?? (backgroundColor == null ? MMColors.cream : MMColors.deepOlive);
    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: backgroundColor == null ? MMColors.heroGradient : null,
        color: backgroundColor,
      ),
      child: initial == null
          ? Icon(Icons.person, size: radius * 1.1, color: fg)
          : Text(initial, style: serif(radius * 0.95, color: fg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = url?.trim();
    final hasUrl = u != null && u.isNotEmpty && Uri.tryParse(u)?.hasScheme == true;
    return Semantics(
      label: 'Profile picture',
      image: true,
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: hasUrl
            ? ClipOval(
                child: Image.network(
                  u,
                  width: radius * 2,
                  height: radius * 2,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _default(),
                  loadingBuilder: (_, child, progress) => progress == null ? child : _default(),
                ),
              )
            : _default(),
      ),
    );
  }
}
