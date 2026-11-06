import 'dart:async';
import 'dart:isolate';

import '../models/bottle_model.dart';
import '../models/color_unit.dart';
import '../models/move_model.dart';
import '../models/puzzle_state.dart';
import 'hint.dart';
import 'solver_config.dart';
import 'solver_result.dart';
import 'puzzle_solver.dart';

/// Handle to an in-flight background solve.
final class SolverRequest {
  SolverRequest._(this.result, this._cancel);

  /// Completes with the result, or with status `cancelled` after [cancel].
  final Future<SolveResult> result;
  final void Function() _cancel;

  void cancel() => _cancel();
}

/// Runs [PuzzleSolver] on a separate isolate so the UI thread never blocks.
/// Cancelling kills the isolate, so a stale search stops consuming CPU.
/// Only plain data crosses the isolate boundary.
class SolverService {
  const SolverService();

  SolverRequest start(
    PuzzleState state, {
    SolverConfig config = const SolverConfig(),
  }) {
    final completer = Completer<SolveResult>();
    final port = ReceivePort();
    Isolate? isolate;
    var finished = false;

    void finish({SolveResult? result, Object? error}) {
      if (finished) return;
      finished = true;
      port.close();
      isolate?.kill(priority: Isolate.immediate);
      if (error != null) {
        completer.completeError(error);
      } else {
        completer.complete(result);
      }
    }

    port.listen((Object? msg) {
      if (msg is List && msg.isNotEmpty && msg[0] is int) {
        finish(result: _decodeResult(msg));
      } else if (msg is List) {
        finish(error: StateError('Solver isolate failed: $msg'));
      } else {
        finish(error: StateError('Solver isolate exited without a result'));
      }
    });

    Isolate.spawn<List<Object?>>(
      _entry,
      [port.sendPort, _encodeState(state), _encodeConfig(config)],
      onError: port.sendPort,
      onExit: port.sendPort,
    ).then((iso) {
      isolate = iso;
      if (finished) iso.kill(priority: Isolate.immediate);
    }, onError: (Object e) => finish(error: e));

    return SolverRequest._(
      completer.future,
      () => finish(result: SolveResult(status: SolverStatus.cancelled)),
    );
  }

  Future<SolveResult> solve(
    PuzzleState state, {
    SolverConfig config = const SolverConfig(),
  }) => start(state, config: config).result;
}

/// Async hint API for the UI. Every call, and every [invalidate] (call it
/// whenever the player moves), supersedes earlier requests: their isolates
/// are killed and their futures resolve to [HintResult.stale], so an old
/// answer can never be shown for a newer position.
class HintController {
  HintController({
    this.service = const SolverService(),
    this.config = const SolverConfig(),
  }) : _planner = HintPlanner(config: config);

  final SolverService service;
  final SolverConfig config;
  final HintPlanner _planner;
  int _generation = 0;
  SolverRequest? _inflight;

  void invalidate() {
    _generation++;
    _inflight?.cancel();
    _inflight = null;
  }

  Future<HintResult> requestHint(PuzzleState state) async {
    invalidate();
    final gen = _generation;

    final cached = _planner.cachedHint(state);
    if (cached != null) return HintResult(HintStatus.available, hint: cached);

    final req = service.start(state, config: config);
    _inflight = req;
    final SolveResult r;
    try {
      r = await req.result;
    } finally {
      if (gen == _generation) _inflight = null;
    }
    if (gen != _generation) return HintResult.stale;
    return _planner.fromSolve(state, r);
  }

  void dispose() => invalidate();
}

// ---- isolate plumbing (plain data only) ----

void _entry(List<Object?> args) {
  final send = args[0] as SendPort;
  final state = _decodeState(args[1] as List<Object?>);
  final config = _decodeConfig(args[2] as List<Object?>);
  final r = const PuzzleSolver().solve(state, config: config);
  send.send(_encodeResult(r));
}

List<Object?> _encodeState(PuzzleState s) => [
  for (final b in s.bottles) [b.capacity, for (final u in b.units) u.id],
];

PuzzleState _decodeState(List<Object?> data) => PuzzleState([
  for (final raw in data)
    BottleModel(
      capacity: (raw as List)[0] as int,
      units: [for (final id in raw.skip(1)) ColorUnit(id as int)],
    ),
]);

List<Object?> _encodeConfig(SolverConfig c) => [
  c.strategy.index,
  c.maxNodes,
  c.maxDuration?.inMicroseconds ?? -1,
  c.bfsNodeBudget,
  c.heuristicWeight,
];

SolverConfig _decodeConfig(List<Object?> d) => SolverConfig(
  strategy: SolverStrategy.values[d[0] as int],
  maxNodes: d[1] as int,
  maxDuration: (d[2] as int) < 0 ? null : Duration(microseconds: d[2] as int),
  bfsNodeBudget: d[3] as int,
  heuristicWeight: d[4] as double,
);

List<Object?> _encodeResult(SolveResult r) => [
  0, // tag: result
  r.status.index,
  r.strategyUsed?.index ?? -1,
  r.isOptimal,
  r.nodesGenerated,
  r.nodesExpanded,
  r.elapsed.inMicroseconds,
  [
    for (final m in r.moves) ...[m.source, m.destination],
  ],
];

SolveResult _decodeResult(List<Object?> d) {
  final flat = (d[7] as List).cast<int>();
  return SolveResult(
    status: SolverStatus.values[d[1] as int],
    strategyUsed: (d[2] as int) < 0 ? null : SolverStrategy.values[d[2] as int],
    isOptimal: d[3] as bool,
    nodesGenerated: d[4] as int,
    nodesExpanded: d[5] as int,
    elapsed: Duration(microseconds: d[6] as int),
    moves: [
      for (var i = 0; i < flat.length; i += 2) MoveModel(flat[i], flat[i + 1]),
    ],
  );
}
