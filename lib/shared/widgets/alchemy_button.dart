import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../features/feedback/feedback_service.dart';

enum AlchemyButtonKind { primary, secondary, quiet }

/// The game's own button: glowing liquid-gold for the main action, glass for
/// the rest. Always at least 56 px tall, so it is easy to hit on any phone.
class AlchemyButton extends StatefulWidget {
  const AlchemyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = AlchemyButtonKind.primary,
    this.subtitle,
    this.expand = true,
  });

  final String label;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onPressed;
  final AlchemyButtonKind kind;
  final bool expand;

  @override
  State<AlchemyButton> createState() => _AlchemyButtonState();
}

class _AlchemyButtonState extends State<AlchemyButton> {
  bool _down = false;

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final primary = widget.kind == AlchemyButtonKind.primary;
    final quiet = widget.kind == AlchemyButtonKind.quiet;
    final fg = primary ? const Color(0xFF2A1A00) : AppColors.textPrimary;

    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, color: fg, size: 22),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              if (widget.subtitle != null)
                Text(
                  widget.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.75),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onPressed == null
            ? null
            : () {
                playUiTap(context);
                widget.onPressed!();
              },
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 90),
          child: Opacity(
            opacity: _enabled ? 1 : 0.45,
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: primary
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.goldLight,
                          AppColors.gold,
                          AppColors.goldDeep,
                        ],
                      )
                    : null,
                color: primary
                    ? null
                    : (quiet ? Colors.transparent : AppColors.glassFillStrong),
                border: primary
                    ? null
                    : Border.all(
                        color: quiet
                            ? Colors.transparent
                            : AppColors.glassBorder,
                      ),
                boxShadow: [
                  if (primary && _enabled)
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.45),
                      blurRadius: 24,
                      offset: const Offset(0, 6),
                    ),
                ],
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// A round glass button with an icon and a caption (undo, hint, ...).
class OrbButton extends StatefulWidget {
  const OrbButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.size = 56,
    this.showLabel = true,
    this.accent,
    this.onDisabledTap,
    this.unavailableReason,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final double size;
  final bool showLabel;
  final Color? accent;

  /// Called when the player taps while the button is unavailable (not while
  /// it is merely busy), so the screen can explain why.
  final VoidCallback? onDisabledTap;

  /// Spoken by screen readers while the button is unavailable.
  final String? unavailableReason;

  @override
  State<OrbButton> createState() => _OrbButtonState();
}

class _OrbButtonState extends State<OrbButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final accent = widget.accent ?? AppColors.cyanGlow;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      hint: enabled ? null : widget.unavailableReason,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: enabled
            ? () {
                playUiTap(context);
                widget.onPressed!();
              }
            : (widget.onPressed == null ? widget.onDisabledTap : null),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: _down ? 0.92 : 1,
                duration: const Duration(milliseconds: 90),
                child: Opacity(
                  opacity: widget.onPressed == null ? 0.4 : 1,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.3, -0.4),
                        colors: [
                          Colors.white.withValues(alpha: 0.26),
                          Colors.white.withValues(alpha: 0.07),
                        ],
                      ),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.55),
                        width: 1.4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.22),
                          blurRadius: 14,
                        ),
                      ],
                    ),
                    child: widget.busy
                        ? Padding(
                            padding: EdgeInsets.all(widget.size * 0.28),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: accent,
                            ),
                          )
                        : Icon(
                            widget.icon,
                            color: AppColors.textPrimary,
                            size: widget.size * 0.46,
                          ),
                  ),
                ),
              ),
              if (widget.showLabel) ...[
                const SizedBox(height: 4),
                Text(
                  widget.label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
