import 'package:flutter/material.dart';

import '../theme.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    required this.color,
    this.icon,
    this.dense = false,
    super.key,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 13, color: color),
            const SizedBox(width: 5),
          ] else ...[
            Container(
              width: dense ? 5 : 6,
              height: dense ? 5 : 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: dense ? 11 : 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(22),
    this.accent,
    super.key,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsets padding;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final borderColor = accent?.withValues(alpha: 0.32) ?? AppColors.borderSoft;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                padding.left,
                padding.top,
                padding.right,
                subtitle == null ? 12 : 6,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title!,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 14.5,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                ],
              ),
            ),
          if (title != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: padding.left),
              child: const Divider(height: 1),
            ),
          Padding(
            padding: title == null
                ? padding
                : EdgeInsets.fromLTRB(
                    padding.left,
                    padding.top,
                    padding.right,
                    padding.bottom,
                  ),
            child: child,
          ),
        ],
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({
    required this.label,
    required this.value,
    this.mono = false,
    this.valueColor,
    this.selectable = false,
    this.copiedHint,
    this.trailing,
    super.key,
  });

  final String label;
  final String value;
  final bool mono;
  final Color? valueColor;
  final bool selectable;
  final String? copiedHint;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 12.5,
      height: 1.5,
      color: valueColor ?? AppColors.text,
      fontFamily: mono ? _monoFamily() : null,
      fontFamilyFallback: mono ? const ['Menlo', 'Consolas', 'Courier New'] : null,
    );
    final valueWidget = selectable
        ? SelectableText(value, style: style)
        : Text(
            value,
            style: style,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style:  TextStyle(
                fontSize: 12,
                color: AppColors.faint,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: valueWidget),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (copiedHint != null) ...[
            const SizedBox(width: 8),
            Text(
              copiedHint!,
              style:  TextStyle(fontSize: 11, color: AppColors.faint),
            ),
          ],
        ],
      ),
    );
  }

  static String _monoFamily() {
    return 'Menlo';
  }
}

class KeyValueChip extends StatelessWidget {
  const KeyValueChip({
    required this.label,
    required this.value,
    this.color,
    super.key,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style:  TextStyle(fontSize: 11, color: AppColors.faint),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: color ?? AppColors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}


class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    required this.message,
    this.title,
    this.color,
    this.icon = Icons.info_outline_rounded,
    this.action,
    super.key,
  });

  final String message;
  final String? title;
  final Color? color;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.amber;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: effectiveColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: effectiveColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: effectiveColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                Text(
                  message,
                  style:  TextStyle(
                    fontSize: 12,
                    height: 1.55,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 12), action!],
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: AppColors.faint),
          const SizedBox(height: 12),
          Text(
            title,
            style:  TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style:  TextStyle(
              fontSize: 12,
              height: 1.6,
              color: AppColors.faint,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
