import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../engine/generator/difficulty.dart';

extension DifficultyStyle on Difficulty {
  String get label => switch (this) {
    Difficulty.easy => 'Easy',
    Difficulty.medium => 'Medium',
    Difficulty.hard => 'Hard',
    Difficulty.expert => 'Expert',
  };

  Color get color => switch (this) {
    Difficulty.easy => const Color(0xFF3DDC97),
    Difficulty.medium => AppColors.gold,
    Difficulty.hard => const Color(0xFFFF7A59),
    Difficulty.expert => AppColors.rose,
  };

  int get pips => index + 1;
}

/// Four pips and a word: how hard the current level is.
class DifficultyIndicator extends StatelessWidget {
  const DifficultyIndicator({
    super.key,
    required this.difficulty,
    this.showLabel = true,
  });

  final Difficulty difficulty;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final c = difficulty.color;
    return Semantics(
      label: 'Difficulty ${difficulty.label}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 4; i++)
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < difficulty.pips
                    ? c
                    : Colors.white.withValues(alpha: 0.14),
                boxShadow: [
                  if (i < difficulty.pips)
                    BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 6),
                ],
              ),
            ),
          if (showLabel) ...[
            const SizedBox(width: 4),
            Text(
              difficulty.label,
              style: TextStyle(
                color: c,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
