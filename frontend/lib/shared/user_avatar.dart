import 'package:flutter/material.dart';

/// Profile picture with a built-in default. Shows the default person avatar when there is no
/// picture, while it loads, and if the image fails to load — so a missing/broken URL never breaks a screen.
class UserAvatar extends StatelessWidget {
  final String? url;
  final double radius;
  final Color? backgroundColor;
  final Color? iconColor;
  const UserAvatar({super.key, this.url, this.radius = 24, this.backgroundColor, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? Theme.of(context).colorScheme.secondaryContainer;
    final fg = iconColor ?? Theme.of(context).colorScheme.onSecondaryContainer;
    final fallback = Icon(Icons.person, size: radius * 1.1, color: fg);
    final u = url?.trim();
    final hasUrl = u != null && u.isNotEmpty && Uri.tryParse(u)?.hasScheme == true;
    return Semantics(
      label: 'Profile picture',
      image: true,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: hasUrl
            ? ClipOval(
                child: Image.network(
                  u,
                  width: radius * 2,
                  height: radius * 2,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => fallback,
                  loadingBuilder: (_, child, progress) => progress == null ? child : fallback,
                ),
              )
            : fallback,
      ),
    );
  }
}
