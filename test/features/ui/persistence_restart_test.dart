import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/generator/generator_version.dart';
import 'package:prism_pour/engine/generator/level_generator.dart';
import 'package:prism_pour/engine/models/move_model.dart';
import 'package:prism_pour/engine/progression/star_rating.dart';
import 'package:prism_pour/features/game/application/board_controller.dart';
import 'package:prism_pour/features/game/application/game_session.dart';
import 'package:prism_pour/features/game/rendering/bottle_style.dart';
import 'package:prism_pour/features/game/rendering/liquid_palette.dart';
import 'package:prism_pour/features/progress/application/providers.dart';
import 'package:prism_pour/features/progress/data/progress_repository.dart';
import 'package:prism_pour/features/progress/data/sqlite_progress_repository.dart';
import 'package:prism_pour/features/progress/domain/player_progress.dart';
import 'package:prism_pour/features/settings/application/settings_providers.dart';
import 'package:prism_pour/features/settings/domain/app_settings.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;

import '../../support/sqlite_support.dart';
import '../../support/test_app.dart';

/// One launch of the app on a database file. [close] ends it.
class Launch {
  Launch._(this.container, this.repo, this.calls);

  final ProviderContainer container;
  final SqliteProgressRepository repo;
  final List<int> calls;

  GameSession get session => container.read(gameSessionProvider);
  PlayerProgress get progress => container.read(progressProvider);

  /// Let queued database writes finish (they run as microtasks/futures).
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await repo.flush();
  }

  /// A graceful shutdown. (A kill right after a committed move is the same
  /// thing, because every move is written as soon as it is committed.)
  Future<void> close() async {
    await settle();
    container.dispose();
    await repo.close();
  }

  static Future<Launch> start(String path, {LevelLoader? loader}) async {
    final calls = <int>[];
    final repo = repoAt(path);
    final container = await readyContainer(
      repo: repo,
      feedback: RecordingFeedback(),
      levelLoader: (n) async {
        calls.add(n);
        return (loader ?? (m) async => const LevelGenerator().generate(m))(n);
      },
    );
    return Launch._(container, repo, calls);
  }
}

/// Taps source then destination and lets the pour "finish".
void play(GameSession s, int from, int to) {
  final b = s.board!;
  b.tapBottle(from);
  final o = b.tapBottle(to);
  expect(o.kind, TapKind.pourStarted, reason: '$from -> $to must be legal');
  b.finishPour(b.activePour!.token);
}

const level1 = [(0, 2), (1, 0), (1, 2)];
const level2 = [(0, 3), (2, 0), (1, 2), (1, 3)];

void main() {
  group('resuming an unfinished game after a restart', () {
    test('the exact position, move history and undo stack come back', () async {
      final path = dbPathIn(tempDir());
      final a = await Launch.start(path);
      await a.session.startLevel(2);
      play(a.session, 0, 3);
      play(a.session, 2, 0);
      final stateBefore = a.session.board!.committedState;
      final original = a.session.level!.puzzle;
      await a.close();

      final b = await Launch.start(path);
      expect(
        b.progress.continueGame!.level,
        2,
        reason: 'Continue knows the level',
      );
      expect(b.progress.continueGame!.moves.length, 2);
      await b.session.startLevel(2);
      expect(b.session.moves, 2);
      expect(b.session.board!.committedState, stateBefore);
      expect(b.session.level!.puzzle, original);
      expect(b.session.canUndo, isTrue);
      expect(b.session.board!.committedMoves, const [
        MoveModel(0, 3),
        MoveModel(2, 0),
      ]);
      await b.close();
    });

    test(
      'undo works across the restart, all the way back to the start',
      () async {
        final path = dbPathIn(tempDir());
        final a = await Launch.start(path);
        await a.session.startLevel(2);
        play(a.session, 0, 3);
        play(a.session, 2, 0);
        final original = a.session.level!.puzzle;
        await a.close();

        final b = await Launch.start(path);
        await b.session.startLevel(2);
        b.session.undo();
        expect(b.session.moves, 1);
        await b.settle();
        expect(
          (await repoAt(path).loadProgress()).saved[2]!.moves.length,
          1,
          reason: 'the undo is saved too',
        );
        b.session.undo();
        expect(b.session.moves, 0);
        expect(b.session.board!.committedState, original);
        await b.settle();
        expect(
          (await repoAt(path).loadProgress()).saved,
          isEmpty,
          reason: 'nothing left to resume',
        );
        await b.close();
      },
    );

    test('a restored game can simply be played on to the win', () async {
      final path = dbPathIn(tempDir());
      final a = await Launch.start(path);
      await a.session.startLevel(1);
      play(a.session, 0, 2);
      await a.close();

      final b = await Launch.start(path);
      await b.session.startLevel(1);
      play(b.session, 1, 0);
      play(b.session, 1, 2);
      expect(b.session.status, SessionStatus.completed);
      expect(b.session.result!.moves, 3);
      expect(b.session.result!.stars, 3);
      await b.close();
    });

    test(
      'the same colours are used after a restart (the seed is saved)',
      () async {
        final path = dbPathIn(tempDir());
        final a = await Launch.start(path);
        await a.session.startLevel(8);
        play(
          a.session,
          a.session.board!.engine.getLegalMoves().first.source,
          a.session.board!.engine.getLegalMoves().first.destination,
        );
        final palette = a.session.palette!;
        final seed = a.session.level!.seed;
        await a.close();
        final b = await Launch.start(path);
        await b.session.startLevel(8);
        expect(b.session.level!.seed, seed);
        expect(b.session.palette, palette);
        await b.close();
      },
    );

    test(
      'a kill the moment a pour starts still keeps that move (commit first)',
      () async {
        final path = dbPathIn(tempDir());
        final a = await Launch.start(path);
        await a.session.startLevel(1);
        a.session.board!.tapBottle(0);
        a.session.board!.tapBottle(2); // pour STARTED; animation never finishes
        expect(a.session.board!.isPouring, isTrue);
        await a.close();

        final b = await Launch.start(path);
        await b.session.startLevel(1);
        expect(b.session.moves, 1);
        expect(
          b.session.board!.isPouring,
          isFalse,
          reason: 'no half-finished animation is restored',
        );
        await b.close();
      },
    );

    test('rapid play: 30 moves in a row are all saved', () async {
      final path = dbPathIn(tempDir());
      final a = await Launch.start(path);
      await a.session.startLevel(150); // 10 colours: not solvable by chance
      var made = 0;
      while (made < 30 && a.session.status == SessionStatus.playing) {
        final m =
            a.session.board!.engine.getLegalMoves()[made %
                a.session.board!.engine.getLegalMoves().length];
        play(a.session, m.source, m.destination);
        made++;
      }
      final moves = a.session.board!.committedMoves;
      await a.close();
      final b = await Launch.start(path);
      await b.session.startLevel(150);
      expect(b.session.board!.committedMoves, moves);
      expect(moves.length, 30);
      await b.close();
    });

    test('several unfinished levels are remembered; Continue follows the last one played', () async {
      final path = dbPathIn(tempDir());
      final a = await Launch.start(path);
      await a.session.startLevel(1);
      play(a.session, 0, 2);
      await a.session.startLevel(2);
      play(a.session, 0, 3);
      await a.close();
      final b = await Launch.start(path);
      expect(b.progress.saved.keys.toSet(), {1, 2});
      expect(b.progress.continueGame!.level, 2);
      await b.session.startLevel(1);
      expect(b.session.moves, 1);
      await b.close();
    });
  });

  group('the saved puzzle never changes, even if the generator does', () {
    test(
      'a restored game uses the STORED puzzle and does not call the generator',
      () async {
        final path = dbPathIn(tempDir());
        final a = await Launch.start(path);
        await a.session.startLevel(8);
        final original = a.session.level!.puzzle;
        final m = a.session.board!.engine.getLegalMoves().first;
        play(a.session, m.source, m.destination);
        await a.close();

        // "A new version of the game": the generator now makes a DIFFERENT
        // level 8 (here, level 9's board) and its calls are counted.
        final b = await Launch.start(
          path,
          loader: (n) async => const LevelGenerator().generate(n + 1),
        );
        await b.session.startLevel(8);
        expect(b.calls, isEmpty, reason: 'the generator was never asked');
        expect(b.session.level!.levelNumber, 8);
        expect(b.session.level!.puzzle, original);
        expect(b.session.moves, 1);
        expect(b.session.board!.committedMoves, [m]);
        await b.close();
      },
    );

    test(
      'a NEW game of that level uses whatever the generator now produces',
      () async {
        final path = dbPathIn(tempDir());
        final a = await Launch.start(path);
        await a.session.startLevel(8);
        final old = a.session.level!.puzzle;
        await a.close();
        final b = await Launch.start(
          path,
          loader: (n) async => const LevelGenerator().generate(n + 1),
        );
        await b.session.startLevel(8); // nothing saved (no moves were made)
        expect(b.calls, [8]);
        expect(b.session.level!.puzzle, isNot(old));
        await b.close();
      },
    );

    test('restoring works even if the generator is broken', () async {
      final path = dbPathIn(tempDir());
      final a = await Launch.start(path);
      await a.session.startLevel(8);
      final m = a.session.board!.engine.getLegalMoves().first;
      play(a.session, m.source, m.destination);
      await a.close();
      final b = await Launch.start(
        path,
        loader: (n) async => throw StateError('generator crashed'),
      );
      await b.session.startLevel(8);
      expect(b.session.status, SessionStatus.playing);
      expect(b.session.moves, 1);
      await b.close();
    });

    test(
      'the saved difficulty and par (so stars) come from the save',
      () async {
        final path = dbPathIn(tempDir());
        final a = await Launch.start(path);
        await a.session.startLevel(8);
        final par = a.session.par;
        final difficulty = a.session.level!.difficulty;
        final m = a.session.board!.engine.getLegalMoves().first;
        play(a.session, m.source, m.destination);
        await a.close();
        final b = await Launch.start(
          path,
          loader: (n) async => const LevelGenerator().generate(n + 1),
        );
        await b.session.startLevel(8);
        expect(b.session.par, par);
        expect(b.session.level!.difficulty, difficulty);
        await b.close();
      },
    );

    test('a pre-snapshot save is rebuilt ONLY if the generator version matches', () async {
      final path = dbPathIn(tempDir());
      final seed = repoAt(path);
      final p0 = await seed.loadProgress();
      final same = SavedGame(
        level: 3,
        variant: 0,
        generatorVersion: kGeneratorVersion,
        moves: const [MoveModel(0, 2)],
      );
      final other = SavedGame(
        level: 4,
        variant: 0,
        generatorVersion: kGeneratorVersion + 7,
        moves: const [MoveModel(0, 1)],
      );
      await seed.saveProgress(p0.withSavedGame(same).withSavedGame(other));
      await seed.close();

      final a = await Launch.start(path);
      await a.session.startLevel(3);
      expect(
        a.session.moves,
        1,
        reason: 'same generator version: rebuilt exactly',
      );
      await a.session.startLevel(4);
      expect(
        a.session.moves,
        0,
        reason:
            'different version: the puzzle could differ, so it is NOT replayed',
      );
      expect(a.session.notice, contains('could not be restored'));
      await a.settle();
      expect(a.progress.saved.containsKey(4), isFalse);
      await a.close();
    });
  });

  group('damaged or incomplete saves', () {
    Future<String> savedLevel(String path, int level, {int moves = 3}) async {
      final a = await Launch.start(path);
      await a.session.startLevel(level);
      var n = 0;
      while (n < moves) {
        final m =
            a.session.board!.engine.getLegalMoves()[n %
                a.session.board!.engine.getLegalMoves().length];
        play(a.session, m.source, m.destination);
        n++;
      }
      await a.close();
      return path;
    }

    test('a move that is no longer legal rewinds to the last good move and says so', () async {
      final path = dbPathIn(tempDir());
      await savedLevel(path, 8, moves: 3);
      final db = await rawDb(path);
      final row = (await db.query('saved_games')).single;
      final moves = jsonDecode(row['moves']! as String) as List;
      moves[1] = [5, 5]; // a pour of a bottle onto itself
      await db.update('saved_games', {'moves': jsonEncode(moves)});
      await db.close();

      final b = await Launch.start(path);
      await b.session.startLevel(8);
      expect(b.session.status, SessionStatus.playing);
      expect(b.session.moves, 1, reason: 'restored up to the last valid move');
      expect(b.session.notice, contains('rewound'));
      await b.settle();
      expect(
        (await repoAt(path).loadProgress()).saved[8]!.moves.length,
        1,
        reason: 'the rewound game replaces the damaged one',
      );
      await b.close();
    });

    test(
      'a stored board that disagrees with the moves: the moves win, quietly',
      () async {
        final path = dbPathIn(tempDir());
        await savedLevel(path, 8, moves: 2);
        final db = await rawDb(path);
        await db.update('saved_games', {
          'current_state': jsonEncode([
            [4, 1],
            [4],
          ]),
        });
        await db.close();
        final b = await Launch.start(path);
        await b.session.startLevel(8);
        expect(b.session.moves, 2);
        expect(b.session.notice, isNull);
        await b.close();
      },
    );

    test('an unusable snapshot with a wrong generator version starts the level fresh', () async {
      final path = dbPathIn(tempDir());
      await savedLevel(path, 8, moves: 2);
      final db = await rawDb(path);
      await db.update('saved_games', {
        'original_state': '[[2,1,1,1]]',
        'generator_version': kGeneratorVersion + 1,
      });
      await db.close();
      final b = await Launch.start(path);
      await b.session.startLevel(8);
      expect(b.session.status, SessionStatus.playing);
      expect(b.session.moves, 0);
      expect(b.session.notice, isNotNull);
      await b.close();
    });

    test(
      'a solved-looking save with no moves left is just an empty game',
      () async {
        final path = dbPathIn(tempDir());
        await savedLevel(path, 8, moves: 1);
        final db = await rawDb(path);
        await db.update('saved_games', {'moves': '[]'});
        await db.close();
        final b = await Launch.start(path);
        await b.session.startLevel(8);
        expect(b.session.moves, 0);
        expect(b.session.status, SessionStatus.playing);
        await b.close();
      },
    );

    test(
      'completely garbled save rows never stop the app from starting',
      () async {
        final path = dbPathIn(tempDir());
        await savedLevel(path, 8, moves: 1);
        final db = await rawDb(path);
        await db.update('saved_games', {
          'moves': '}{',
          'original_state': 'x',
          'current_state': 'y',
          'seed': 'abc',
        });
        await db.close();
        final b = await Launch.start(path);
        expect(b.progress.saved, isEmpty);
        await b.session.startLevel(8);
        expect(b.session.status, SessionStatus.playing);
        expect(b.session.moves, 0);
        await b.close();
      },
    );
  });

  group('completion is saved once, and unlocks the next level', () {
    test(
      'after winning and restarting, the next numbered level is current',
      () async {
        final path = dbPathIn(tempDir());
        final a = await Launch.start(path);
        await a.session.startLevel(1);
        for (final m in level1) {
          play(a.session, m.$1, m.$2);
        }
        await a.close();

        final b = await Launch.start(path);
        expect(b.progress.currentLevel, 2);
        expect(b.progress.recordOf(1)!.stars, 3);
        expect(b.progress.recordOf(1)!.bestMoves, 3);
        expect(b.progress.saved, isEmpty, reason: 'the finished game is gone');
        await b.session.startLevel(b.progress.currentLevel);
        expect(b.session.level!.levelNumber, 2);
        await b.close();
      },
    );

    test('winning removes the saved game in the SAME write as recording the result', () async {
      final path = dbPathIn(tempDir());
      final a = await Launch.start(path);
      await a.session.startLevel(1);
      for (final m in level1.take(2)) {
        play(a.session, m.$1, m.$2);
      }
      await a.settle();
      final db = await rawDb(path);
      expect(
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM saved_games'),
        ),
        1,
      );
      play(a.session, 1, 2); // the winning move
      await a.settle();
      expect(
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM saved_games'),
        ),
        0,
      );
      expect(
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM completed_levels'),
        ),
        1,
      );
      await db.close();
      await a.close();
    });

    test('completing the same level again can never pay out twice', () async {
      final path = dbPathIn(tempDir());
      final a = await Launch.start(path);
      await a.session.startLevel(1);
      for (final m in level1) {
        play(a.session, m.$1, m.$2);
      }
      await a.settle();
      final starsAfterFirst = a.progress.totalStars;
      expect(starsAfterFirst, 3);
      expect(a.session.result!.starsImproved, isTrue);

      for (var round = 0; round < 3; round++) {
        await a.session.startLevel(1, resume: false);
        for (final m in level1) {
          play(a.session, m.$1, m.$2);
        }
        expect(
          a.session.result!.starsImproved,
          isFalse,
          reason: 'no reward the second time',
        );
        expect(a.session.result!.isNewBest, isFalse);
      }
      await a.settle();
      expect(a.progress.totalStars, starsAfterFirst);
      expect(a.progress.completedCount, 1);
      expect(a.progress.currentLevel, 2);
      expect(
        a.progress.recordOf(1)!.completions,
        4,
        reason: 'only the statistic counts repeats',
      );
      await a.close();

      final b = await Launch.start(path);
      expect(b.progress.totalStars, 3);
      expect(b.progress.recordOf(1)!.completions, 4);
      await b.close();
    });

    test('a worse replay never lowers a saved result', () async {
      final path = dbPathIn(tempDir());
      final a = await Launch.start(path);
      await a.session.startLevel(2);
      for (final m in level2) {
        play(a.session, m.$1, m.$2);
      }
      expect(a.session.result!.stars, 3);
      await a.session.startLevel(2, resume: false);
      for (final m in const [
        (0, 3),
        (3, 4),
        (4, 3),
        (3, 4),
        (2, 0),
        (1, 2),
        (1, 4),
      ]) {
        play(a.session, m.$1, m.$2);
      }
      expect(a.session.result!.stars, 2);
      await a.close();
      final b = await Launch.start(path);
      expect(b.progress.recordOf(2)!.stars, 3);
      expect(b.progress.recordOf(2)!.bestMoves, 4);
      await b.close();
    });

    test('winning a level the player had already won, via a restored save, does not re-reward', () async {
      final path = dbPathIn(tempDir());
      final a = await Launch.start(path);
      await a.session.startLevel(1);
      for (final m in level1) {
        play(a.session, m.$1, m.$2);
      }
      await a.settle();
      // A stale saved game for the already-completed level appears
      // (for example, from a crash between two writes in an older version).
      final db = await rawDb(path);
      await db.insert('saved_games', {
        'level': 1,
        'variant': 0,
        'generator_version': kGeneratorVersion,
        'moves': jsonEncode([
          [0, 2],
          [1, 0],
          [1, 2],
        ]),
        'saved_order': 0,
      });
      await db.close();
      await a.close();
      final b = await Launch.start(path);
      expect(
        b.progress.saved,
        isEmpty,
        reason: 'a completed level never offers a stale save',
      );
      expect(b.progress.totalStars, 3);
      await b.close();
    });
  });

  group('unlocked bottle designs and settings', () {
    test('unlocks are stored, and a selected design is remembered', () async {
      final path = dbPathIn(tempDir());
      final seed = repoAt(path);
      var p = await seed.loadProgress();
      for (var l = 1; l <= 5; l++) {
        p = p.withCompletion(level: l, stars: 3, moves: 10);
      }
      expect(p.unlockedStyles, contains('crystal_prism'));
      await seed.saveProgress(p);
      await seed.close();

      final a = await Launch.start(path);
      expect(a.progress.unlockedStyles, contains('crystal_prism'));
      a.container
          .read(appSettingsProvider.notifier)
          .setBottleStyle('crystal_prism');
      await a.close();

      final b = await Launch.start(path);
      expect(
        b.container.read(appSettingsProvider).bottleStyleId,
        'crystal_prism',
      );
      expect(b.container.read(bottleStyleProvider), BottleStyles.crystalPrism);
      await b.close();
    });

    test('a style that was not earned is never shown, even if it is saved as selected', () async {
      final path = dbPathIn(tempDir());
      final seed = repoAt(path);
      await seed.loadProgress();
      await seed.saveSettings(const AppSettings(bottleStyleId: 'royal_glass'));
      await seed.close();
      final a = await Launch.start(path);
      expect(
        a.container.read(bottleStyleProvider),
        BottleStyles.alchemyClassic,
      );
      await a.close();
    });

    test('winning the level that earns a style unlocks it durably', () async {
      final path = dbPathIn(tempDir());
      final seed = repoAt(path);
      var p = await seed.loadProgress();
      for (var l = 2; l <= 5; l++) {
        p = p.withCompletion(level: l, stars: 3, moves: 9);
      }
      await seed.saveProgress(p);
      await seed.close();
      final a = await Launch.start(path);
      expect(
        a.progress.isStyleUnlocked('crystal_prism'),
        isFalse,
        reason: '12 stars so far',
      );
      await a.session.startLevel(1);
      for (final m in level1) {
        play(a.session, m.$1, m.$2);
      }
      await a.close();
      final db = await rawDb(path);
      final ids = [
        for (final r in await db.query('unlocked_styles')) r['style_id'],
      ];
      expect(ids, contains('crystal_prism'));
      await db.close();
    });

    test('all settings survive a restart', () async {
      final path = dbPathIn(tempDir());
      final a = await Launch.start(path);
      final n = a.container.read(appSettingsProvider.notifier);
      n.setSoundEffects(false);
      n.setHaptics(false);
      n.setColorAssist(
        a.container.read(appSettingsProvider).colorAssist == ColorAssist.both
            ? ColorAssist.off
            : ColorAssist.both,
      );
      await a.close();
      final b = await Launch.start(path);
      final s = b.container.read(appSettingsProvider);
      expect(s.soundEffects, isFalse);
      expect(s.haptics, isFalse);
      expect(s.colorAssist, ColorAssist.both);
      await b.close();
    });
  });

  group('hint statistics', () {
    test(
      'requests and shown hints are counted per level and survive a restart',
      () async {
        final path = dbPathIn(tempDir());
        final a = await Launch.start(path);
        await a.session.startLevel(3);
        await a.session.requestHint();
        await a.session.requestHint();
        await a.settle();
        expect(a.progress.hintsOf(3).requested, 2);
        expect(a.progress.hintsOf(3).shown, 2);
        final m = a.session.board!.engine.getLegalMoves().first;
        play(a.session, m.source, m.destination);
        await a.session.requestHint();
        await a.close();

        final b = await Launch.start(path);
        expect(b.progress.hintsOf(3).requested, 3);
        expect(b.progress.hintsOf(3).shown, 3);
        expect(b.progress.totalHintsShown, 3);
        expect(b.progress.hintsOf(4).requested, 0);
        await b.close();
      },
    );

    test('hints used during an attempt are reported on its result', () async {
      final path = dbPathIn(tempDir());
      final a = await Launch.start(path);
      await a.session.startLevel(1);
      await a.session.requestHint();
      for (final m in level1) {
        play(a.session, m.$1, m.$2);
      }
      expect(a.session.result!.hintsUsed, 1);
      expect(
        a.session.result!.stars,
        StarRating.starsFor(moves: 3, par: 3),
        reason: 'hints never change stars',
      );
      await a.close();
    });
  });

  group('unlimited level progression', () {
    test('levels far beyond any plausible maximum can be played, saved and resumed', () async {
      for (final level in [1000000, 4294967296, 1 << 40, 1 << 62]) {
        final path = dbPathIn(tempDir(), 'g$level.db');
        final a = await Launch.start(path);
        await a.session.startLevel(level);
        expect(a.session.status, SessionStatus.playing, reason: 'level $level');
        final original = a.session.level!.puzzle;
        final m = a.session.board!.engine.getLegalMoves().first;
        play(a.session, m.source, m.destination);
        await a.close();

        final b = await Launch.start(path);
        expect(b.progress.continueGame!.level, level);
        await b.session.startLevel(level);
        expect(b.session.level!.levelNumber, level);
        expect(b.session.level!.puzzle, original);
        expect(b.session.moves, 1);
        await b.close();
      }
    });

    test('a huge level can be completed and recorded', () async {
      final path = dbPathIn(tempDir());
      final a = await Launch.start(path);
      final level = 1 << 50;
      await a.session.startLevel(level);
      final solution = const LevelGenerator().generate(level).solution;
      for (final m in solution) {
        play(a.session, m.source, m.destination);
      }
      expect(a.session.status, SessionStatus.completed);
      await a.close();
      final b = await Launch.start(path);
      expect(b.progress.recordOf(level)!.bestMoves, solution.length);
      await b.close();
    });

    test(
      'levels are generated lazily: only the requested level is generated',
      () async {
        final path = dbPathIn(tempDir());
        final a = await Launch.start(path);
        await a.session.startLevel(12);
        expect(a.calls, [12]);
        await a.close();
      },
    );

    test(
      'a long career: 300 levels completed, restart, the next one is 301',
      () async {
        final path = dbPathIn(tempDir());
        final seed = repoAt(path);
        final p = PlayerProgress(
          records: {
            for (var l = 1; l <= 300; l++)
              l: const LevelRecord(stars: 2, bestMoves: 25),
          },
        );
        await seed.loadProgress();
        await seed.saveProgress(p);
        await seed.close();
        final a = await Launch.start(path);
        expect(a.progress.currentLevel, 301);
        await a.session.startLevel(a.progress.currentLevel);
        expect(a.session.level!.levelNumber, 301);
        expect(a.calls, [301]);
        await a.close();
      },
    );
  });

  group('never resetting progress by accident', () {
    test(
      'a read failure at start-up is surfaced and nothing is overwritten',
      () async {
        final path = dbPathIn(tempDir());
        final seed = repoAt(path);
        final p0 = await seed.loadProgress();
        await seed.saveProgress(
          p0
              .withCompletion(level: 1, stars: 3, moves: 3)
              .withCompletion(level: 2, stars: 2, moves: 8),
        );
        await seed.close();

        final flaky = _FlakyRepo(repoAt(path));
        final c = await readyContainerAllowingFailure(flaky);
        expect(
          c.read(bootstrapProvider).hasError,
          isTrue,
          reason: 'the splash shows "try again"',
        );
        expect(
          flaky.saves,
          0,
          reason: 'no empty default state was ever written over real data',
        );
        c.dispose();
        await flaky.inner.close();

        final back = await repoAt(path).loadProgress();
        expect(back.records.keys, [1, 2]);
      },
    );

    test(
      'after the transient failure passes, the real progress loads',
      () async {
        final path = dbPathIn(tempDir());
        final seed = repoAt(path);
        final p0 = await seed.loadProgress();
        await seed.saveProgress(
          p0.withCompletion(level: 1, stars: 3, moves: 3),
        );
        await seed.close();
        final flaky = _FlakyRepo(repoAt(path));
        final c = await readyContainerAllowingFailure(flaky);
        flaky.fail = false;
        c.invalidate(bootstrapProvider);
        final boot = await c.read(bootstrapProvider.future);
        expect(boot.progress.recordOf(1), isNotNull);
        c.dispose();
        await flaky.inner.close();
      },
    );

    test('a damaged database file starts fresh, keeps a backup and tells the player', () async {
      final dir = tempDir();
      final path = dbPathIn(dir);
      final seed = repoAt(path);
      final p0 = await seed.loadProgress();
      await seed.saveProgress(p0.withCompletion(level: 1, stars: 3, moves: 3));
      await seed.close();
      // Overwrite the file with junk (a damaged write).
      final bytes = List<int>.filled(8192, 7);
      await rawFile(path).writeAsBytes(bytes);

      final a = await Launch.start(path);
      final boot = await a.container.read(bootstrapProvider.future);
      expect(boot.progress.currentLevel, 1);
      expect(boot.notices.single, contains('damaged'));
      expect(a.container.read(startupNoticesProvider), isNotEmpty);
      a.container.read(startupNoticesProvider.notifier).dismiss();
      expect(a.container.read(startupNoticesProvider), isEmpty);
      await a.session.startLevel(1);
      play(a.session, 0, 2);
      await a.close();
      final b = await Launch.start(path);
      expect(b.progress.continueGame!.moves.length, 1);
      await b.close();
      expect(
        dir.listSync().where((f) => f.path.contains('.corrupt-')).length,
        1,
      );
    });

    test(
      'a failed save keeps the game playable and the next save catches up',
      () async {
        final path = dbPathIn(tempDir());
        final inner = repoAt(path);
        final flaky = _FlakyRepo(inner)
          ..fail = false
          ..failSaves = true;
        final c = await readyContainer(
          repo: flaky,
          levelLoader: (n) async => const LevelGenerator().generate(n),
        );
        final s = c.read(gameSessionProvider);
        await s.startLevel(1);
        play(s, 0, 2); // the disk write fails; the game must not notice
        expect(s.moves, 1);
        expect(s.status, SessionStatus.playing);
        flaky.failSaves = false;
        play(s, 1, 0);
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        await inner.flush();
        final back = await repoAt(path).loadProgress();
        expect(
          back.saved[1]!.moves.length,
          2,
          reason: 'the later save included everything',
        );
        c.dispose();
        await inner.close();
      },
    );
  });
}

/// Wraps a real repository and fails on demand.
class _FlakyRepo implements ProgressRepository {
  _FlakyRepo(this.inner);

  final SqliteProgressRepository inner;
  bool fail = true; // loads fail
  bool failSaves = false;
  int saves = 0;

  @override
  Future<PlayerProgress> loadProgress() async {
    if (fail) throw StateError('disk read error');
    return inner.loadProgress();
  }

  @override
  Future<AppSettings> loadSettings() async {
    if (fail) throw StateError('disk read error');
    return inner.loadSettings();
  }

  @override
  Future<void> saveProgress(PlayerProgress progress) async {
    saves++;
    if (failSaves) throw StateError('disk full');
    return inner.saveProgress(progress);
  }

  @override
  Future<void> saveSettings(AppSettings settings) =>
      inner.saveSettings(settings);

  @override
  Future<void> flush() => inner.flush();

  @override
  Future<void> close() => inner.close();

  @override
  List<String> takeNotices() => inner.takeNotices();
}

/// A container whose start-up load may fail (the usual helper awaits it).
Future<ProviderContainer> readyContainerAllowingFailure(
  ProgressRepository repo,
) async {
  final c = ProviderContainer(
    overrides: [progressRepositoryProvider.overrideWithValue(repo)],
  );
  try {
    await c.read(bootstrapProvider.future);
  } catch (_) {
    // expected: the provider is now in its error state
  }
  return c;
}

File rawFile(String path) => File(path);
