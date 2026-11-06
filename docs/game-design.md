# Prism Pour — Game Design

## Core loop
The player sees a row of glass bottles ("flasks") holding stacked layers of coloured liquid. The goal is to sort the liquids so every flask contains a single colour (or is empty).

## Rules (canonical, enforced by the pure Dart engine)
- A flask has a fixed **capacity** (default 4 layers).
- A pour moves the **top contiguous run** of one colour from a source to a target flask.
- A pour is legal only if: source is non-empty, source ≠ target, target is not full, and the target is empty or its top colour equals the source's top colour.
- The amount poured is `min(run length, free space in target)`.
- A level is **solved** when every flask is empty or completely full of one colour.
- A level is **stuck** when no legal pour exists and it is not solved.

## Progression
- Unlimited procedurally generated levels, deterministic from a level number + seed, so a level can be regenerated rather than stored.
- Difficulty scales via colour count, flask count, empty-flask count, and capacity.
- Every generated level is verified solvable by the solver before being served.

## Player aids (planned)
Undo, restart, add an extra empty flask (limited), hint (solver-driven).

## Visual identity
- Original glass flasks with refraction highlights, rim glow and liquid surface waves — drawn with CustomPainter, no copied artwork.
- Dark "alchemy lab" theme by default; light theme supported from day one.
- Liquid colours must stay distinguishable (including a colour-blind-safe palette option — planned).

## Audio / effects (planned)
Pour loop, glass clink on completion, soft UI sounds, particle sparkle on a completed flask. All assets bundled; no network.

## Non-goals (v1)
Accounts, online leaderboards, ads, in-app purchases, backend.


## Scoring (implemented)
`StarRating` in `lib/engine/progression/star_rating.dart` is the single source of truth; the completion and settings screens show these numbers.

- **Par** = the length of the best known solution of the level. It is proven shortest for the tutorials and small boards; for larger boards it is the best the solver found, so it is an upper bound on the true optimum.
- **3 stars**: moves <= ceil(par x 1.25) (never less than par).
- **2 stars**: moves <= ceil(par x 1.75).
- **1 star**: the level is solved.
- **Moves** are the pours on the board when the level is solved. An undone pour is not counted. Hints, restarts and pauses never change the rating.
- A replay keeps the best stars and the fewest moves ever achieved, independently.

## Progression (implemented)
- Levels unlock in order: level n is playable once every earlier level is completed. The current level is the first not completed. There is no last level; level select shows chapters of ten and keeps producing more.
- One unfinished game per level is remembered (the 10 most recent). It is stored as the list of committed moves and restored by replaying them through the engine, so it is exact. A save from another generator version, or with an illegal move, is discarded safely.
- **Continue** resumes the last played unfinished level; **Start over** discards its save.

## Gameplay assistance (implemented)
All assists are free: no ads, purchases or currency.
- **Undo** takes back the last pour, any number of times down to the start. The board and move counter change at once; the liquid is shown flowing back, and pressing Undo again simply skips that picture. The undo history is the saved move list, so it survives closing the app.
- **Hint** asks the real solver for the next move from the CURRENT position and highlights the two bottles. It never plays the move. If the position cannot be solved, or the search runs out of its budget, it says so instead of guessing.
- **Restart** deals the level again exactly as it was (same number, same seed). With moves on the board it asks first.
- **Pause** locks the board; nothing is lost and resuming is exact.
- **Move counter** counts successful pours only. Selecting, deselecting and illegal taps never count.
- **Extra bottle booster (optional, off by default).** Settings > Gameplay adds a Bottle button that gives the level one more EMPTY bottle, after a confirmation. The win rule and solver are unchanged (an empty bottle never blocks a win). Because it makes levels easier, a level finished this way earns at most 1 star, and its best-move record is never set below par. Restart removes the bottle. Standard play is untouched when the setting is off.
- A button that cannot be used right now (nothing to undo, paused, a pour in progress) says why when tapped.

## Alchemy Journey (implemented)
Theme: a magical laboratory where the player gradually restores colour and light to a dark world. As levels are completed the backdrop of every screen gains colour, chapter by chapter:

| Chapter | Levels | Look |
| --- | --- | --- |
| Midnight Lab | 1-10 | the dark world: deep indigo, violet and cyan glow |
| Crystal Cavern | 11-25 | icy blue-teal, glittering motes |
| Enchanted Garden | 26-50 | deep greens, golden-lime light |
| Celestial Observatory | 51-90 | purple night sky, gold stars |
| Golden Laboratory | 91-150 | warm amber and gold: all colour restored |

The chapters are data (`Journey.chapters`). After the last, the journey starts a new lap: the same chapters, hue-shifted, titled with a numeral ("Midnight Lab II"), so no level number is ever past the end. The home screen shows the current chapter and the levels left to the next; finishing the level that reaches a milestone announces "NEW CHAPTER" with a short line of story and a reward chime. The scene stays dark in every chapter so text remains readable.

## Bottle collection (implemented)
Five original cosmetic designs unlock with stars (the milestones of play): Alchemy Classic (free), Crystal Prism 15, Royal Glass 45, Verdant Vial 80 and Starlit Flask 130. The equipped design is used on the board. A locked or unknown design saved in settings falls back to the free one, and an unlocked design is never taken away. A design is purely visual: silhouette, glass and neck ring. It cannot change capacity, rules, par or stars (tests check that the engine and board controller never reference rendering, and that identical moves give identical results in every design). The completion screen announces a newly earned design and plays the reward chime.

## Sound and music (implemented)
All audio is original, synthesised by `tool/generate_audio.py` (see `assets/audio/README.md`); nothing is sampled or licensed.
- Effects: bottle select, glass movement, soft liquid pouring (stops with the animation), a gentle two-tone "no" for an impossible pour, level complete, and a reward chime for a new bottle or chapter.
- Optional ambient music: a 32-second seamless loop, **off by default**.
- Settings: Sound effects, Music, Haptics, Reduce motion, colour-blind assistance and High contrast are all independent switches.
- Sounds are preloaded once, players are reused, music pauses when the app leaves the foreground, and a missing audio device turns audio off quietly instead of breaking the game.

## Visual effects (implemented)
Selection and hint halos, completion shimmer and sparkles, pour stream/splash/ripples, tiny rising bubbles and a shimmering surface in resting liquid, drifting motes, a victory burst and gentle screen transitions. Decorative motion (bubbles, motes) stops with Reduce motion, during a pour and in the background; High contrast removes the motes and adds a firm bottle outline and colour dividers.

## Screens
Splash, Home, Level selection, Gameplay (HUD, undo, hint, restart, pause), Pause menu, Level completion, Bottle collection, Settings. Developer tools (Bottle Lab, Animation Lab) are reachable from Settings.
