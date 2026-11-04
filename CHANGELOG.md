# Changelog

All notable changes to this project will be documented in this file.

## [1.1.0] - 2026-11-04

### Changed
- Hints and "Show solution" search about twice as fast: a layout and its
  mirror image are now one position for the solver (they are the same number
  of moves from the exit). The slowest first hint went from ~0.24 s to
  ~0.11 s on a desktop, i.e. from ~5 s to ~2.5 s on a Kobo; most take well
  under a second. Hints stay optimal (checked on 4,800 positions), though
  when two moves are equally good the one suggested may differ.
- A hint that needs a search shows a progress bar when it takes a moment.
- Following the hints, undoing back along them or restarting no longer
  searches again.

## [1.0.3] - 2026-11-03

### Changed
- Picks up game-common 1.11.0: the shared on-screen keyboard (where used)
  gives every key the same letter size, and the no-repeat history helper.

## [1.0.2] - 2026-11-02

### Changed
- Picks up game-common 1.10.0: the shared Tools → Games menu also lists
  the games' new "· multiplayer" entries under Party & quiz.

## [1.0.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.0.0] - 2026-11-02

### Added
- First release: the classic sliding-block puzzle (Klotski, « L'Âne rouge »)
  on a 4×5 tray. Bring the big 2×2 block down to the gap in the bottom wall
  by sliding the other blocks out of its way.
- One move is one block going anywhere it can reach, even round a corner;
  moving the same block again straight after is the same move. The optimum
  of every level is counted that way (the Red Donkey: 81 moves).
- Classics: the Red Donkey and three other traditional openings, plus the
  four hardest starts the generator found (up to 138 moves).
- 1600 generated levels, 400 per difficulty, graded by their optimal number
  of moves: Easy (5–15), Medium (16–35), Hard (36–60) and Expert (61–138).
  Every level is checked to be solvable in exactly its stated optimum.
- Tap a block, then tap one of the dotted squares it can reach; or swipe a
  block to slide it straight as far as it goes.
- Moves counter against the optimum, Undo, Restart, timer and auto-save.
- Hint (two taps: mark the block and its destination, then play it), always
  along an optimal solution from the current position.
- Show solution: step through an optimal solution, forwards and back.
- "New game" opens the next unsolved level; a level picker and solved
  counts per difficulty; a Daily Challenge.
