import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';

/// "Keep me signed in on this device" tick box. Ticked: the sign-in is remembered (renews while you use the app,
/// up to 30 days idle). Unticked: you are signed out when the page is closed or reloaded.
class KeepSignedInBox extends StatefulWidget {
  final bool onDark;
  const KeepSignedInBox({super.key, this.onDark = false});

  @override
  State<KeepSignedInBox> createState() => _KeepSignedInBoxState();
}

class _KeepSignedInBoxState extends State<KeepSignedInBox> {
  @override
  Widget build(BuildContext context) {
    final color = widget.onDark ? MMColors.cream : MMColors.deepOlive;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => TokenStore.remember = !TokenStore.remember),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Checkbox(
            value: TokenStore.remember,
            activeColor: widget.onDark ? MMColors.cream : MMColors.deepOlive,
            checkColor: widget.onDark ? MMColors.deepOlive : MMColors.cream,
            side: BorderSide(color: color, width: 1.6),
            onChanged: (v) => setState(() => TokenStore.remember = v ?? true),
          ),
          Flexible(
            child: Text('Keep me signed in on this device',
                style: TextStyle(color: color, fontSize: 14)),
          ),
        ]),
      ),
    );
  }
}
