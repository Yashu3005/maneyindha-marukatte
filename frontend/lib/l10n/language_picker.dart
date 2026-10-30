import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_strings.dart';
import 'locale_provider.dart';

Future<void> showLanguageSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => const _LanguageSheet(),
  );
}

class _LanguageSheet extends ConsumerWidget {
  const _LanguageSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localeProvider).languageCode;
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(context.tr('Choose language'), style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        for (final code in AppStrings.codes)
          ListTile(
            title: Text(AppStrings.nativeNames[code] ?? code),
            subtitle: Text(AppStrings.englishNames[code] ?? code),
            trailing: code == current ? const Icon(Icons.check_circle) : null,
            onTap: () {
              ref.read(localeProvider.notifier).choose(code);
              Navigator.pop(context);
            },
          ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

/// A row for the Profile menus: "Language" with the current language's own name underneath.
class LanguageTile extends ConsumerWidget {
  const LanguageTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(localeProvider).languageCode;
    return ListTile(
      leading: const Icon(Icons.translate),
      title: Text(context.tr('Language')),
      subtitle: Text(AppStrings.nativeNames[code] ?? code),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showLanguageSheet(context),
    );
  }
}

/// A small text button with the current language, for screens before sign-in.
class LanguageButton extends ConsumerWidget {
  final bool onDark;
  const LanguageButton({super.key, this.onDark = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(localeProvider).languageCode;
    final color = onDark ? const Color(0xFFEDEBDD) : null;
    return TextButton.icon(
      style: color == null ? null : TextButton.styleFrom(foregroundColor: color),
      onPressed: () => showLanguageSheet(context),
      icon: const Icon(Icons.translate, size: 18),
      label: Text(AppStrings.nativeNames[code] ?? code),
    );
  }
}
