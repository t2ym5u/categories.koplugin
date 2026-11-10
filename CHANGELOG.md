# Changelog

## [1.2.0] - 2026-11-10

### Added
- Twice as many French categories: 1,974 (was 962), about 120 more in
  each of the eight packs. The game remembers the last 2,500 categories
  it dealt (was 1,500), so it goes through all of them before repeating.

## [1.1.3] - 2026-11-09

### Fixed
- A language tried once in the game no longer sticks for good: the game
  now starts in KOReader's language (French when KOReader is in French),
  and a language picked in the game holds until KOReader's language changes.

## [1.1.2] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.1.1] - 2026-11-04

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.

## [1.1.0] - 2026-11-03

### Added
- About twice as many categories: 962 in French and 962 in English (was
  457 / 479), about 120 per pack — new ones such as *a character from
  Molière*, *a préfecture*, *a Paris metro station*, *a Tube station*,
  *a character from Roald Dahl*, *what the gargoyles gossip about*…

### Changed
- The categories already drawn are remembered from one game to the next
  (one memory per content language): new games bring new categories, and
  none comes back until the whole selection has been played.

## [1.0.2] - 2026-11-02

### Changed
- Picks up game-common 1.10.0: the shared Tools → Games menu also lists
  the games' new "· multiplayer" entries under Party & quiz.

## [1.0.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.0.0] - 2026-10-30

### Added
- First release: Categories (Petit Bac) — the reader draws a weighted letter and 6–12 categories, players write their answers on paper (or one types them on the reader), Stop! or the timer ends the round.
- Scoring screen with one page per player and big Unique / Shared / None cells, configurable points (2/1, 10/5, 3/1), running totals and a results screen with Next round / New game.
- 457 French and 479 English categories in 8 packs (Classic, Fun, Geography, History & famous people, Pop culture, Food, Absurd, Kids), selectable with their counts; optional hard letters; timer off or 1–5 minutes.
- Scoring labels at a readable size, wrapped, paged on small screens; round-over buttons stacked in landscape.
- Player names remembered, game in progress saved.
- Interface in English, French, Spanish and German; content in French or English.
