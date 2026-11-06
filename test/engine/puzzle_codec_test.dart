import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/generator/level_generator.dart';
import 'package:prism_pour/engine/models/bottle_model.dart';
import 'package:prism_pour/engine/models/color_unit.dart';
import 'package:prism_pour/engine/models/move_model.dart';
import 'package:prism_pour/engine/models/puzzle_codec.dart';
import 'package:prism_pour/engine/models/puzzle_state.dart';

void main() {
  group('puzzles', () {
    test('round trip, including empty and partly filled bottles', () {
      final s = PuzzleState.fromIds([
        [1, 2],
        [],
        [3, 3, 3, 3],
      ]);
      expect(PuzzleCodec.decode(PuzzleCodec.encode(s)), s);
    });

    test('mixed capacities survive', () {
      final s = PuzzleState([
        BottleModel(capacity: 2, units: const [ColorUnit(1)]),
        BottleModel(capacity: 6, units: const [ColorUnit(2), ColorUnit(2)]),
      ]);
      expect(PuzzleCodec.decode(PuzzleCodec.encode(s)), s);
    });

    test('every generated level round-trips exactly', () {
      for (final l in [1, 3, 6, 40, 150, 999999, 1 << 40]) {
        final p = const LevelGenerator().generate(l).puzzle;
        expect(
          PuzzleCodec.decode(PuzzleCodec.encode(p)),
          p,
          reason: 'level $l',
        );
      }
    });

    test('the encoding is plain JSON data', () {
      expect(
        PuzzleCodec.encode(
          PuzzleState.fromIds([
            [1, 2],
            [],
          ]),
        ),
        [
          [4, 1, 2],
          [4],
        ],
      );
    });

    test('damaged input is rejected, never half-accepted', () {
      for (final bad in <Object?>[
        null,
        5,
        'x',
        <Object?>[],
        [<Object?>[]],
        [
          ['a'],
        ],
        [
          [0, 1],
        ],
        [
          [4, -1],
        ],
        [
          [4, 1.5],
        ],
        [
          [2, 1, 1, 1],
        ],
        [
          [4, 9999999],
        ],
        [
          [65, 1],
        ],
        [
          [4, 1],
          7,
        ],
        List.generate(65, (_) => [4]),
      ]) {
        expect(
          () => PuzzleCodec.decode(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });
  });

  group('moves', () {
    test('round trip', () {
      const moves = [MoveModel(0, 2), MoveModel(1, 0), MoveModel(11, 3)];
      expect(PuzzleCodec.decodeMoves(PuzzleCodec.encodeMoves(moves)), moves);
      expect(PuzzleCodec.decodeMoves(const []), isEmpty);
    });

    test('damaged input is rejected', () {
      for (final bad in <Object?>[
        null,
        'x',
        5,
        [
          [0],
        ],
        [
          [0, 1, 2],
        ],
        [
          ['a', 1],
        ],
        [
          [-1, 0],
        ],
        [
          [0, 9999],
        ],
        [
          [0.5, 1],
        ],
        [1],
      ]) {
        expect(
          () => PuzzleCodec.decodeMoves(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });

    test('an absurdly long history is refused', () {
      final huge = List.generate(100001, (_) => [0, 1]);
      expect(() => PuzzleCodec.decodeMoves(huge), throwsFormatException);
      expect(PuzzleCodec.decodeMoves(huge, maxMoves: 200000).length, 100001);
    });
  });
}
