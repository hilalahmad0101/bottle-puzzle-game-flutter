# Development Roadmap

Each module is delivered and reviewed separately.

| # | Module | Outcome | Status |
|---|---|---|---|
| 1 | Project setup & architecture | Project, deps, theme, routing, shell, docs | **Done** |
| 2 | Puzzle engine | Models, move validation, pour logic, win/stuck detection + tests | **Done** |
| 3 | Solver | BFS + weighted best-first solver, proven-unsolvable detection, isolate service, hints | **Done** |
| 4 | Level generator | Deterministic unlimited levels, 5 handcrafted tutorials, verified solutions, difficulty grading | **Done** |
| 5 | Game state | `BoardController` + `GameSession` (undo/restart, save/restore, stars, hints) | **Done** (as part of modules 6-7) |
| 6 | Bottle rendering | Glass flask + liquid CustomPainters, 3 styles, palette, accessibility, preview screen | **Done** |
| 7 | Pour animation | Tilt, stream, fill/drain, ripples, speed + reduced-motion settings, interruption safety, lab screen | **Done** |
| 8 | Local storage | SQLite progress, exact-resume saves, versioned migrations, corruption recovery (see `architecture.md`) | **Done** |
| 8b | Gameplay assistance | Undo with reverse-pour animation, solver hints, restart, pause, optional extra-bottle booster (off by default) | **Done** |
| 9 | Audio & effects | Original synthesised sounds + optional music, bubbles/ripples/glow, Alchemy Journey chapters, 5 bottle designs, high contrast | **Done** |
| 10 | Screens & polish | Splash, home, level select, gameplay, pause, completion, collection, settings | **Done** (onboarding and audio still open) |
| 11 | Hardening | Performance profiling, Android release build, iOS check, store prep | Planned |

## Pending decisions
- Audio package (candidates: audioplayers, just_audio, flutter_soloud) — chosen in module 9.
- Colour-blind-safe palette approach.
- Whether to persist settings in SQLite or shared_preferences.
