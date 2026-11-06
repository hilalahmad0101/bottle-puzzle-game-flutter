import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../engine/generator/level_generator.dart';
import '../../../engine/models/move_model.dart';
import '../../../engine/models/puzzle_state.dart';
import '../../../shared/widgets/prism_background.dart';
import '../../settings/application/settings_providers.dart';
import '../animation/animation_settings.dart';
import '../animation/pour_board.dart';
import '../animation/pour_plan.dart';
import '../application/board_controller.dart';
import '../rendering/bottle_style.dart';
import '../rendering/liquid_palette.dart';

class _Scenario {
  const _Scenario(this.name, this.state, this.move);
  final String name;
  final PuzzleState state;
  final MoveModel move;
}

/// Debug bench for the pour animation: pre-built pours of 1-4 units, a real
/// generated level, slow motion, a scrub slider, geometry overlays, state
/// readouts and frame timing. Not part of gameplay.
class AnimationLabScreen extends ConsumerStatefulWidget {
  const AnimationLabScreen({super.key});

  @override
  ConsumerState<AnimationLabScreen> createState() => _AnimationLabScreenState();
}

class _AnimationLabScreenState extends ConsumerState<AnimationLabScreen> {
  static final List<_Scenario> _scenarios = [
    _Scenario(
      '1 unit',
      PuzzleState.fromIds([
        [2, 2, 0, 1],
        [1, 3, 3],
        [0, 0, 1, 2],
        [3, 1],
        [],
        [],
      ]),
      const MoveModel(0, 3),
    ),
    _Scenario(
      '2 units',
      PuzzleState.fromIds([
        [0, 2, 1, 1],
        [3, 1],
        [2, 0, 3, 0],
        [2, 3, 0, 2],
        [],
        [],
      ]),
      const MoveModel(0, 1),
    ),
    _Scenario(
      '3 units',
      PuzzleState.fromIds([
        [2, 1, 1, 1],
        [0, 3, 0, 3],
        [2, 0, 3, 2],
        [],
        [],
      ]),
      const MoveModel(0, 3),
    ),
    _Scenario(
      'Partial',
      PuzzleState.fromIds([
        [3, 1, 1, 1],
        [2, 1, 1],
        [0, 2, 3, 0],
        [],
        [],
      ]),
      const MoveModel(0, 1),
    ),
    _Scenario(
      '4 units',
      PuzzleState.fromIds([
        [1, 1, 1, 1],
        [0, 2, 0, 2],
        [],
        [],
      ]),
      const MoveModel(0, 2),
    ),
    _levelScenario('Level 40', 40),
    _levelScenario('Level 150 (12 bottles)', 150),
  ];

  static _Scenario _levelScenario(String name, int level) {
    final lv = const LevelGenerator().generate(level);
    return _Scenario(name, lv.puzzle, lv.solution.first);
  }

  final _boardKey = GlobalKey<PourBoardState>();
  final _scrub = ValueNotifier<double?>(null);
  final _stats = FrameStats();
  BoardController _controller = BoardController(_scenarios[0].state);
  LiquidPalette _palette = LiquidPalette.forColorIds(
    _scenarios[0].state.colorCounts.keys,
  );
  int _scenario = 0;
  BottleStyle _style = BottleStyles.alchemyClassic;
  ColorAssist _assist = ColorAssist.off;
  double _slow = 1;
  bool _debug = false;
  bool _scrubMode = false;
  final List<String> _log = [];
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_stats.callback);
    _ticker = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) setState(() {});
    });
  }

  void _load(int i) {
    _scenario = i;
    final s = _scenarios[i];
    _palette = LiquidPalette.forColorIds(s.state.colorCounts.keys);
    final old = _controller;
    _controller = BoardController(s.state);
    // The board swaps listeners on rebuild; dispose the old one afterwards.
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _log.clear();
    _scrub.value = null;
    _scrubMode = false;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_stats.callback);
    _scrub.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _note(TapOutcome o) {
    _log.insert(0, o.toString());
    if (_log.length > 6) _log.removeLast();
  }

  Future<void> _playMove() async {
    final m = _scenarios[_scenario].move;
    final c = _controller;
    if (c.isPouring) return;
    // A tap on a not-yet-selected source, a beat for the lift, then the pour.
    if (c.selectedIndex != null) c.tapBottle(c.selectedIndex!);
    setState(() => _note(c.tapBottle(m.source)));
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted || !identical(c, _controller)) return;
    setState(() => _note(c.tapBottle(m.destination)));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(animationSettingsProvider);
    final text = Theme.of(context).textTheme;
    final c = _controller;
    final plan = _boardKey.currentState?.currentPlan;

    return Scaffold(
      appBar: AppBar(title: const Text('Animation Lab')),
      body: PrismBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (var i = 0; i < _scenarios.length; i++)
                    ChoiceChip(
                      key: Key('lab.scenario.$i'),
                      label: Text(_scenarios[i].name),
                      selected: _scenario == i,
                      onSelected: (_) => setState(() => _load(i)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              PourBoard(
                key: _boardKey,
                controller: c,
                palette: _palette,
                style: _style,
                assist: _assist,
                settings: settings,
                timeScaleMultiplier: _slow,
                scrub: _scrub,
                debugOverlay: _debug,
                onTapOutcome: (o) => setState(() => _note(o)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    key: const Key('lab.play'),
                    onPressed: _playMove,
                    child: const Text('Play move'),
                  ),
                  OutlinedButton(
                    key: const Key('lab.undo'),
                    onPressed: () => setState(c.undo),
                    child: const Text('Undo'),
                  ),
                  OutlinedButton(
                    key: const Key('lab.reset'),
                    onPressed: () => setState(c.reset),
                    child: const Text('Reset'),
                  ),
                  OutlinedButton(
                    key: const Key('lab.skip'),
                    onPressed: () => setState(() => c.interruptPour()),
                    child: const Text('Skip'),
                  ),
                  OutlinedButton(
                    key: const Key('lab.pause'),
                    onPressed: () => setState(c.isPaused ? c.resume : c.pause),
                    child: Text(c.isPaused ? 'Resume' : 'Pause'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Speed', style: text.titleSmall),
              const SizedBox(height: 6),
              SegmentedButton<AnimationSpeed>(
                key: const Key('lab.speed'),
                segments: const [
                  ButtonSegment(
                    value: AnimationSpeed.normal,
                    label: Text('Normal'),
                  ),
                  ButtonSegment(
                    value: AnimationSpeed.fast,
                    label: Text('Fast'),
                  ),
                ],
                selected: {settings.speed},
                onSelectionChanged: (s) =>
                    ref.read(appSettingsProvider.notifier).setSpeed(s.first),
              ),
              const SizedBox(height: 10),
              SegmentedButton<MotionPreference>(
                key: const Key('lab.motion'),
                segments: const [
                  ButtonSegment(
                    value: MotionPreference.system,
                    label: Text('System'),
                  ),
                  ButtonSegment(
                    value: MotionPreference.on,
                    label: Text('Reduced'),
                  ),
                  ButtonSegment(
                    value: MotionPreference.off,
                    label: Text('Full'),
                  ),
                ],
                selected: {settings.motion},
                onSelectionChanged: (s) =>
                    ref.read(appSettingsProvider.notifier).setMotion(s.first),
              ),
              const SizedBox(height: 10),
              SegmentedButton<double>(
                key: const Key('lab.slow'),
                segments: const [
                  ButtonSegment(value: 1, label: Text('1x')),
                  ButtonSegment(value: 2, label: Text('2x slower')),
                  ButtonSegment(value: 4, label: Text('4x slower')),
                ],
                selected: {_slow},
                onSelectionChanged: (s) => setState(() => _slow = s.first),
              ),
              const SizedBox(height: 10),
              SegmentedButton<BottleStyle>(
                showSelectedIcon: false,
                segments: [
                  for (final s in BottleStyles.all)
                    ButtonSegment(
                      value: s,
                      label: Text(s.name.split(' ').first),
                    ),
                ],
                selected: {_style},
                onSelectionChanged: (s) => setState(() => _style = s.first),
              ),
              SwitchListTile(
                key: const Key('lab.assist'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Colour-blind symbols'),
                value: _assist != ColorAssist.off,
                onChanged: (v) => setState(
                  () => _assist = v ? ColorAssist.symbols : ColorAssist.off,
                ),
              ),
              SwitchListTile(
                key: const Key('lab.debug'),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Geometry overlay (lip, impact, stream, hollow)',
                ),
                value: _debug,
                onChanged: (v) => setState(() => _debug = v),
              ),
              SwitchListTile(
                key: const Key('lab.scrubMode'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Scrub: freeze and drag through the pour'),
                value: _scrubMode,
                onChanged: (v) => setState(() {
                  _scrubMode = v;
                  _scrub.value = v ? (_scrub.value ?? 0) : null;
                }),
              ),
              if (_scrubMode)
                Slider(
                  key: const Key('lab.scrub'),
                  value: (_scrub.value ?? 0).clamp(0.0, 1.0),
                  onChanged: (v) => setState(() => _scrub.value = v),
                ),
              const SizedBox(height: 8),
              _Readout(
                title: 'State',
                lines: [
                  'phase: ${c.isPaused ? 'paused' : (c.isPouring ? 'pouring' : 'idle')}'
                      '${c.activePour != null ? ' (token ${c.activePour!.token})' : ''}',
                  'selected: ${c.selectedIndex ?? '-'}',
                  'committed moves: ${c.engine.moveCount}   level complete: ${c.levelCompleteVisible}',
                  'last interruption: ${c.lastInterruption?.name ?? '-'}',
                  if (plan != null) ...[
                    'quantity: ${plan.quantity}   side: ${plan.side > 0 ? 'right' : 'left'}   reduced: ${plan.reduced}',
                    'duration: ${plan.duration.toStringAsFixed(2)} s   '
                        'pour: ${(plan.tPourEnd - plan.tApproachEnd).toStringAsFixed(2)} s',
                    'start tilt ${(plan.startTilt * 180 / 3.14159).toStringAsFixed(0)}deg  '
                        'end tilt ${(plan.endTilt * 180 / 3.14159).toStringAsFixed(0)}deg',
                    'now: ${plan.phaseAt(_seconds(plan)).name} @ ${_seconds(plan).toStringAsFixed(2)} s',
                  ],
                ],
              ),
              const SizedBox(height: 8),
              _Readout(
                title:
                    'Frame timing (last ${_stats.count} frames; goal 16.7 ms)',
                lines: [
                  'build ${_stats.avgBuildMs.toStringAsFixed(1)} ms   '
                      'raster ${_stats.avgRasterMs.toStringAsFixed(1)} ms   '
                      'worst ${_stats.worstTotalMs.toStringAsFixed(1)} ms   '
                      'slow frames ${_stats.slowFrames}',
                ],
              ),
              const SizedBox(height: 8),
              _Readout(title: 'Taps', lines: _log.isEmpty ? ['-'] : _log),
            ],
          ),
        ),
      ),
    );
  }

  double _seconds(PourPlan plan) =>
      (_scrub.value ?? (_boardKey.currentState?.progress ?? 0)) * plan.duration;
}

class _Readout extends StatelessWidget {
  const _Readout({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text.titleSmall),
            const SizedBox(height: 4),
            for (final l in lines) Text(l, style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}
