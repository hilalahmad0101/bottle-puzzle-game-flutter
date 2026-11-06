# Prism Pour — Architecture

Flutter (stable) · Dart · Riverpod · go_router · SQLite (sqflite) · CustomPainter. Fully offline, no game engine.

## Layering and dependency rule
```
features/*  ──►  engine/   (pure Dart, no Flutter imports)
    │
    ├──────────►  data/    (SQLite, repositories)
    └──────────►  app/, core/, shared/
```
- `engine/` must never import `package:flutter` or `dart:ui`. This keeps it unit-testable, fast, and runnable in an isolate (level generation / solving).
- `features/` own UI and state. They talk to `engine/` and `data/` only through Riverpod providers.
- `data/` exposes repository interfaces; features depend on the interface, not on sqflite.

## Folder structure
```
lib/
  main.dart                     entry point, ProviderScope
  app/                          1. application configuration
    app.dart                    MaterialApp.router
    router/                     go_router config + route paths
    theme/                      colours, spacing, light/dark ThemeData, theme mode provider
  core/                         constants, small utilities
  engine/                       2. pure Dart puzzle engine
    models/                     Flask, Layer, PuzzleState, Move
    rules/                      move validation, pour application, win/stuck detection
    solver/                     3. solver (BFS/A*, hints, solvability check)
    generator/                  4. procedural generation (seeded, difficulty curve)
  data/                         8. local storage
    database/                   sqflite open/migrations
    repositories/               progress & settings repositories
  features/
    home/presentation/          screens
    game/
      application/              5. game state (Riverpod notifiers: state, undo stack)
      rendering/                6. flask/liquid CustomPainters
      animation/                7. pour animation controllers/curves
      presentation/             game screen + widgets
    settings/presentation/
    effects/
      audio/                    9. sound playback service
      visual/                   particles, glow
  shared/widgets/               10. reusable widgets
assets/ sounds/ animations/ images/
docs/  test/{app,engine,data}/
```
Empty module folders hold a `.gitkeep` until their module is implemented.

## Key decisions
| Concern | Choice | Reason |
|---|---|---|
| State | flutter_riverpod 3 | Testable, compile-safe, no BuildContext coupling |
| Navigation | go_router | Declarative, deep-link ready; paths centralised in `AppRoutes` |
| Persistence | sqflite | Structured progress, migrations; works on Android and iOS |
| Rendering | CustomPainter | Full control of glass/liquid look; no engine needed |
| Levels | Seeded generation, not stored | Unlimited levels, tiny save data, reproducible |
| Heavy work | Isolates | Generate/solve off the UI thread |

## Solver (`engine/solver/`)
- `PuzzleSolver`: synchronous search over exact `PourRules`. BFS (proven shortest when it finishes), weighted best-first (valid but not proven shortest), or `auto` (BFS within a node budget, then best-first).
- Visited states use an exact canonical key (`StateKeyer`: bottles sorted, so bottle order is ignored). Paths keep real bottle indices. `unsolvable` is only reported when proven (counting argument or exhausted space); limits give `budgetExceeded`.
- Every solution is replayed through `GameEngine` before it is returned.
- `SolverService` runs the solver on a separate isolate and can kill it; `HintController` discards stale answers when the player moves (`invalidate()`); `HintPlanner` caches the solution path and re-solves from the real state when the player deviates.

## Level generation (`engine/generator/`)
`LevelGenerator.generate(n, {variant})` is a pure function of the level number, variant and `kGeneratorVersion`: no clock, no global state, and its own PRNG (mulberry32) instead of `dart:math` Random, whose sequence is not guaranteed across SDKs.
- **Levels 1-5**: handcrafted (`tutorial_levels.dart`), solutions proven shortest by exhaustive BFS and re-verified at load.
- **Level 6+**: `LevelCurve` maps the number to colours (3..10), 2 empty bottles, capacity 4 (max 12 bottles) and a target score. The ramp runs from level 6 to ~126, then plateaus at the maximum board size.
- **Candidate boards**: up to 6 colours use reverse construction (scramble a solved board; each reverse step is accepted only if the real engine confirms the forward move is legal and reproduces the previous state exactly). Larger boards are random classic boards accepted only after the solver finds a solution (reverse walks almost never end in a classic layout at that size).
- **Every candidate**: validated (`LevelValidator`: capacity, colour counts, empties, not completed, full engine replay), graded on one fixed reference solver run so both methods are comparable, and accepted if its score is near the target. Cost is bounded by counts (<= 16 attempts, capped solver nodes), never by wall-clock time, so results stay deterministic. If nothing is acceptable a verified fallback board is returned and flagged.
- **Stored per level** (`GeneratedLevel`): number, seed, variant, generator version, difficulty, original state, fingerprint, solution, metrics, method. It has `toJson`/`fromJson` for the storage module.
- **Repeat avoidance**: the canonical level never depends on history. `LevelService.levelAvoidingRecent` may substitute a recorded `variant` when a layout was seen recently. Fingerprints are 64-bit hashes of the canonical layout; uniqueness is not guaranteed.
- **Changing any tuning, grading or algorithm requires bumping `kGeneratorVersion`** (golden tests will fail as a reminder).

## Bottle rendering (`features/game/rendering/`)
Visual direction: "Midnight Alchemy Laboratory" (faceted glass, illuminated neck rings, soft glow).
- **Geometry**: `BottleGeometry` is the one interface rendering, effects and the future pour animation use (outline, hollow `cavity`, liquid column, `unitRect(i)`, `mouth`, `pivot`, ring, facet edges). `FacetedBottleGeometry` builds it from a `BottleSpec` (fractions of the box), so a style is data. Liquid occupies only the straight body, so a full bottle ends below the neck, and every unit has the same height.
- **Styles** (`BottleStyles`): Alchemy Classic (brass ring), Crystal Prism (angular, iridescent ring), Royal Glass (double gold ring and jewel). Adding one means adding a spec and finish, not new geometry code.
- **Painters**: `LiquidLayerPainter` (clipped to the cavity; layers are `LiquidLayerSpan`s in fractional units so a pour animation can grow them), `GlassReflectionPainter`/`GlassPainting` (back and front glass), `CustomBottlePainter` (composes them), `BottleSelectionEffect`, `CompletedBottleEffect`.
- **Performance**: the glass is recorded once into Pictures and shared by every bottle with the same style/size/capacity (`BottleLayerCache`, LRU). Liquid is the only per-bottle drawing. `BottleView` puts glass+liquid, selection halo and completion effect in separate `RepaintBoundary`s; the selection lift is a `Transform` (no repaint); effects stop their tickers when idle and honour reduce-motion.
- **Colours**: `LiquidPalette` has 12 named colours; a level with N colours takes the N most mutually distinct (greedy farthest-point in L*a*b*), so look-alikes only meet in the largest levels. Colour-blind aid: `ColorAssist` (symbols, patterns, both).
- **Preview**: `/preview` (home screen "Bottle Lab") shows empty, partial, mixed, full and capacity-6 bottles in every style and assist mode.

## Pour animation (`features/game/animation/`, `features/game/application/`)
**Commit, then animate.** `BoardController` applies a move to the engine the instant the second bottle is tapped. The animation is a visual replay of that `MoveResult`; it never changes game state and the game never waits for it. So any interruption (app backgrounded, screen closed, reset, undo, pause, layout change) just drops the replay: there is nothing to roll back or re-apply, and a save taken at any moment is already final. While a pour shows, all taps return `busy`. Finish callbacks carry a token, so a late callback from an old pour is ignored.
- **`PourPlan`**: a pure function (`frameAt(seconds)`) of the `MoveResult`, the board layout and the settings. It describes the bottle's pose, both liquids as fractional `LiquidLayerSpan`s, the stream curve, ripples/slosh and particles. Because it depends only on seconds, timing is device independent and fully unit-testable. Last frame == committed state exactly.
- **Physically based tilt**: `LiquidVolumeModel` solves, on the real hollow polygon, the world-horizontal plane that conserves each layer's volume at any tilt, and the tilt at which liquid reaches the lip (about 73 deg for a full bottle, rising as it empties; capped at ~103 deg so the base never leaves the board). The stream is pinned to the real lip point.
- **Rendering**: `PourBoard` draws resting bottles normally; for the two bottles in a pour it hides them (`Offstage`) and `PourOverlayPainter` draws them, the stream and particles in one repaint layer driven by the `AnimationController` (no widget rebuilds per frame). Draw order puts the stream inside the destination glass. The tilt-aware liquid renderer is only used when tilted or rippling; at rest the original renderer is used, so the hand-over is pixel-identical.
- **Settings**: `AnimationSettings` (Normal/Fast speed; reduced motion system/on/off). Reduced motion keeps the level change but removes flying, tilting, streams and splashes.
- **Debug**: `/animation-lab` (home screen "Animation Lab") has 1-4 unit pours, a 12-bottle level, slow motion, a scrub slider, a geometry overlay, state readouts and frame timing.

## Game UI (`features/*/presentation`, `shared/widgets`)
- **Identity**: "Midnight Alchemy Laboratory". `AlchemyBackground` (gradient, glows, drifting motes), `GlassPanel`, `AlchemyButton`/`OrbButton`, `AlchemySwitch`/`AlchemySegments`, `StarRow`, `DifficultyIndicator`, `AlchemyToast`, and a logo drawn with the game's own bottle renderer. Decorative looping motion is gated by one switch (`ambientMotionProvider`) and obeys reduced motion.
- **Navigation**: go_router with one fade/rise transition. `/` splash -> `/home` -> `/levels`, `/play` -> `/complete`, `/collection`, `/settings`. The splash appears on the first frame (nothing is awaited before `runApp`) and leaves when its animation and the storage load are both done.
- **Real state, no mock data**: `GameSession` wraps the `BoardController` and owns level loading (off the UI thread via `LevelService`), save-after-every-move, restore by replay, completion + stars, and solver hints. Screens only read it and call its methods.
- **Persistence**: `ProgressRepository` (interface) with a `shared_preferences` JSON implementation, which the planned SQLite storage module can replace without touching screens. Corrupt data is skipped, never crashes start-up.
- **Responsive**: `BoardLayout.compute(maxHeight:)` chooses 1-3 rows to maximise bottle size for the available width AND height (portrait, landscape, tablet); the HUD becomes a side panel in landscape; menu screens scroll and scale their text instead of overflowing; HUD text is clamped to 1.35x system text scale. Tests assert this on seven screen shapes with a simulated notch.
- **Audio**: only haptics and a system click are implemented (Flutter built-ins, no new packages or permissions). Music is shown as unavailable until an audio module bundles tracks.

## Gameplay assistance (`engine/rules/extra_bottle.dart`, `features/game/application/`)
- `BoardController` is the single authority. Undo is `engine.undoMove()` plus an `ActivePour(isUndo: true)` carrying `MoveResult.reversed`, which `PourBoard` animates like any pour; the board is already committed, so an interrupted undo animation changes nothing. Repeated undo drops the running picture and starts the next.
- `GameSession.whyUnavailable(GameAction)` is the one place that knows why undo/hint/restart/booster cannot run; the buttons call `explainUnavailable` on a disabled tap (message + reject haptic).
- The extra bottle is isolated in `ExtraBottle` (append one empty bottle) and `BoardController.addExtraBottle` (rebuild the engine on `initial + empty bottle` and replay the moves, so counts, undo history and indices are unchanged). It only runs when `AppSettings.extraBottleBooster` (default false) is on and the player confirmed. `SavedGame.boosted` (SQLite schema v3, column `booster`) stores it; the saved original board stays the level as dealt. Boosted attempts are scored through `GameSession.assistedStarCap` and a par floor on best moves.

## Audio (`features/audio/`)
`AudioManager` is the only thing that decides whether a sound plays (settings read at the moment of use, a 45 ms de-bounce per effect, foreground only). It talks to an `AudioBackend` interface; the real one (`AudioplayersBackend`) creates its players once in `preload`, reuses them (a 2-player round-robin pool for overlapping effects) and mixes with other apps' audio. Tests use `FakeAudioBackend`, so no test touches a device. A backend failure is logged once and silences audio for the session. `AudioGuard` (app builder) preloads at start, forwards lifecycle events and re-syncs the music with the settings; `FeedbackService` is the single entry point for gameplay (haptic + sound).

## Alchemy Journey (`features/journey/`)
`Journey.chapters` is a const list of `JourneyStage` (name, length, palette, motes). `Journey.at(completedLevels)` is O(chapters) for any 64-bit number and repeats the list as hue-shifted laps. `journeyProvider` derives from the first uncompleted level and is safe before progress has loaded. `AlchemyBackground` blends palettes when the chapter changes (listener, not build). `GameSession._complete` computes `LevelResult.newStyleIds` and `newChapter` from the progress before and after the completion.

## Liquid life and high contrast (`features/game/rendering/`)
`PourBoard` owns ONE shared 40-second clock for every bottle's `LiquidLifeEffect` (bubbles + surface shimmer, own repaint layer). It runs only when `liquidLife` is on, no pour is animating and the app is foregrounded. `HighContrastOverlay` is static.

## State model (planned)
Immutable `PuzzleState` (list of flasks) + pure `applyMove(state, move) -> state`. The game notifier keeps `current`, an undo stack, and a transient animation state separate from logical state: the logical move is applied instantly; the animation is presentation only.

## Persistence (planned)
SQLite tables: `progress` (highest level, stats), `saved_game` (level id, seed, serialized state, undo stack). Settings (theme mode, sound) use the same DB or shared_preferences. Currently the theme mode is in-memory only.

## Testing strategy
Engine: exhaustive unit tests (rules, solver, generator solvability). Data: repository tests against sqflite in-memory/FFI. UI: widget tests for navigation and screens (`test/app`). Painters: golden tests once rendering lands.

## Known tooling note
The Dart analysis server crashes (JSON framing error) when the project path contains non-ASCII characters such as "—" (this folder is named "Prism Pour — Alchemy Lab"). `flutter analyze` must be run from an ASCII-only path, or the folder renamed. Tests and builds are unaffected.
