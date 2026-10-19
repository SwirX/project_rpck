import 'package:flutter/material.dart';

import '../../ui/app_settings.dart';
import '../../ui/rpck_top_bar.dart';

/// Row used by every settings group.
class SettingTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SettingTile({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.hairline),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: palette.muted, size: 21),
        title: Text(
          title,
          style: TextStyle(color: palette.onSurface, fontSize: 14.5),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
        trailing: trailing,
      ),
    );
  }
}

/// A labelled group of settings.
class SettingGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final String? footer;

  const SettingGroup({
    super.key,
    required this.title,
    required this.children,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(title, padding: const EdgeInsets.fromLTRB(4, 22, 4, 10)),
        for (final child in children) child,
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
            child: Text(
              footer!,
              style: TextStyle(color: context.palette.muted, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

/// Switch bound to a boolean on [AppSettings].
class SettingSwitch extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final bool value;
  final AppSettings Function(AppSettings next) mutate;

  const SettingSwitch({
    super.key,
    required this.title,
    required this.icon,
    required this.value,
    required this.mutate,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return SettingTile(
      title: title,
      subtitle: subtitle,
      icon: icon,
      onTap: () => AppSettingsScope.update(context, mutate),
      trailing: Switch(
        value: value,
        // The switch reads the same value as the row, so tapping either works.
        onChanged: (_) => AppSettingsScope.update(context, mutate),
      ),
    );
  }
}

/// Choice between a small set of named options.
class SettingChoice<T> extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final T value;
  final List<(T, String)> options;
  final AppSettings Function(AppSettings next, T chosen) mutate;

  const SettingChoice({
    super.key,
    required this.title,
    required this.icon,
    required this.value,
    required this.options,
    required this.mutate,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return SettingTile(
      title: title,
      subtitle: subtitle,
      icon: icon,
      onTap: () => _pick(context),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _labelFor(value),
            style: TextStyle(color: context.palette.muted, fontSize: 13),
          ),
          const Icon(Icons.chevron_right_rounded, size: 20),
        ],
      ),
    );
  }

  String _labelFor(T option) => options
      .firstWhere(
        (candidate) => candidate.$1 == option,
        orElse: () => (value, ''),
      )
      .$2;

  Future<void> _pick(BuildContext context) async {
    final chosen = await showModalBottomSheet<T>(
      context: context,
      backgroundColor: context.palette.surfaceHigh,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (option, label) in options)
              RadioListTile<T>(
                value: option,
                groupValue: value,
                title: Text(label),
                onChanged: (selected) => Navigator.of(context).pop(selected),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;
    await AppSettingsScope.update(context, (current) => mutate(current, chosen));
  }
}

/// Read-only row showing a resolved path or value.
class SettingReadout extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final String? actionLabel;

  const SettingReadout({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.onTap,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SettingTile(
      title: title,
      subtitle: value,
      icon: icon,
      onTap: onTap,
      trailing: actionLabel == null
          ? null
          : Text(
              actionLabel!,
              style: TextStyle(color: RpckTheme.primary, fontSize: 13),
            ),
    );
  }
}