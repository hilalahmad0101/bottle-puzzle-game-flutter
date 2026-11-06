import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../features/feedback/feedback_service.dart';

/// A pill switch: a glass track with a golden liquid thumb.
class AlchemySwitch extends StatelessWidget {
  const AlchemySwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: label,
      onTap: enabled ? () => onChanged!(!value) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                playUiTap(context);
                onChanged!(!value);
              }
            : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 56, minHeight: 48),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 52,
              height: 30,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                color: value
                    ? AppColors.gold.withValues(alpha: 0.28)
                    : Colors.white.withValues(alpha: 0.08),
                border: Border.all(
                  color: value ? AppColors.gold : AppColors.glassBorder,
                ),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: value
                        ? const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [AppColors.goldLight, AppColors.goldDeep],
                          )
                        : null,
                    color: value ? null : Colors.white38,
                    boxShadow: [
                      if (value)
                        BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of mutually exclusive choices drawn as glass pills.
class AlchemySegments<T> extends StatelessWidget {
  const AlchemySegments({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.itemKeyPrefix,
  });

  /// value -> label, in display order.
  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onChanged;

  /// If set, each segment gets the key `Key('$prefix.$value')`.
  final String? itemKeyPrefix;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          for (final e in options.entries)
            Expanded(
              child: Semantics(
                button: true,
                selected: e.key == selected,
                label: e.value,
                child: GestureDetector(
                  key: itemKeyPrefix == null
                      ? null
                      : Key(
                          '$itemKeyPrefix.${e.key is Enum ? (e.key as Enum).name : e.key}',
                        ),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    playUiTap(context);
                    onChanged(e.key);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: e.key == selected
                          ? const LinearGradient(
                              colors: [AppColors.goldLight, AppColors.gold],
                            )
                          : null,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        e.value,
                        maxLines: 1,
                        style: TextStyle(
                          color: e.key == selected
                              ? const Color(0xFF2A1A00)
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A screen title bar in the game's style: back orb, title, optional trailing.
class AlchemyAppBar extends StatelessWidget {
  const AlchemyAppBar({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: onBack == null
                ? null
                : Semantics(
                    button: true,
                    label: 'Back',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onBack,
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.08),
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ),
          SizedBox(width: 56, child: trailing),
        ],
      ),
    );
  }
}
