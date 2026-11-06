import 'package:flutter/material.dart';

import '../../../engine/models/bottle_model.dart';
import '../../../engine/models/color_unit.dart';
import '../../../shared/widgets/prism_background.dart';
import '../rendering/bottle_style.dart';
import '../rendering/bottle_view.dart';
import '../rendering/liquid_palette.dart';

/// Visual test bench for bottle styles. Not part of gameplay.
class BottlePreviewScreen extends StatefulWidget {
  const BottlePreviewScreen({super.key});

  @override
  State<BottlePreviewScreen> createState() => _BottlePreviewScreenState();
}

class _BottlePreviewScreenState extends State<BottlePreviewScreen> {
  BottleStyle _style = BottleStyles.alchemyClassic;
  ColorAssist _assist = ColorAssist.off;
  int _colors = 6;
  int? _selected;
  bool _showCompleted = true;

  List<_Sample> _samples(LiquidPalette palette) {
    BottleModel b(List<int> ids, {int cap = 4}) =>
        BottleModel(capacity: cap, units: ids.map(ColorUnit.new));
    final n = _colors;
    int c(int i) => i % n;
    return [
      _Sample('Empty', b([])),
      _Sample('1 unit', b([c(0)])),
      _Sample('Partial', b([c(1), c(1)])),
      _Sample('Mixed', b([c(0), c(1), c(2), c(3)])),
      _Sample('Layers', b([c(2), c(2), c(4), c(5)])),
      _Sample('Full', b([c(3), c(3), c(3), c(3)])),
      _Sample('Cap 6', b([c(0), c(1), c(1), c(2), c(3), c(3)], cap: 6)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = LiquidPalette.forColorIds(List.generate(_colors, (i) => i));
    final samples = _samples(palette);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Bottle Lab')),
      body: PrismBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text('Style', style: text.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<BottleStyle>(
                key: const Key('preview.styles'),
                showSelectedIcon: false,
                segments: [
                  for (final s in BottleStyles.all)
                    ButtonSegment(value: s, label: Text(s.name)),
                ],
                selected: {_style},
                onSelectionChanged: (v) => setState(() => _style = v.first),
              ),
              const SizedBox(height: 16),
              Text('Colour assist', style: text.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final a in ColorAssist.values)
                    ChoiceChip(
                      key: Key('preview.assist.${a.name}'),
                      label: Text(a.name),
                      selected: _assist == a,
                      onSelected: (_) => setState(() => _assist = a),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Colours in level: $_colors', style: text.titleSmall),
              Slider(
                key: const Key('preview.colors'),
                min: 3,
                max: 10,
                divisions: 7,
                value: _colors.toDouble(),
                label: '$_colors',
                onChanged: (v) => setState(() => _colors = v.round()),
              ),
              SwitchListTile(
                key: const Key('preview.completed'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Completed glow on full bottles'),
                value: _showCompleted,
                onChanged: (v) => setState(() => _showCompleted = v),
              ),
              const SizedBox(height: 8),
              Text('Tap a bottle to select it', style: text.bodySmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 22,
                alignment: WrapAlignment.center,
                children: [
                  for (var i = 0; i < samples.length; i++)
                    GestureDetector(
                      key: Key('preview.bottle.$i'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          setState(() => _selected = _selected == i ? null : i),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 18), // room for the lift
                          SizedBox(
                            width: 84,
                            height: 200,
                            child: BottleView(
                              bottle: samples[i].bottle,
                              palette: palette,
                              style: _style,
                              assist: _assist,
                              selected: _selected == i,
                              completed: _showCompleted ? null : false,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(samples[i].label, style: text.labelMedium),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Palette for this level', style: text.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final e in palette.entries)
                    _Swatch(id: e.key, color: e.value, assist: _assist),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sample {
  const _Sample(this.label, this.bottle);
  final String label;
  final BottleModel bottle;
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.id, required this.color, required this.assist});

  final int id;
  final LiquidColor color;
  final ColorAssist assist;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.base,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
        ),
        const SizedBox(height: 4),
        Text(color.name, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
