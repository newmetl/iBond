# Levels — design

Date: 2026-08-08
Status: implemented

## Goal

Replace the single fixed map with 10 levels of increasing difficulty. The
pre-levels game is calibrated as level 7. Difficulty ramps by introducing one
mechanic at a time and then scaling counts and map size.

## Decisions (Wojtek, 2026-08-08)

- Death retries the **same level** ("Restart"); progress is never reset by dying.
- The current level **persists across app launches** (`UserDefaults`, key
  `currentLevel`, via `@AppStorage`).
- Finishing a level shows "Level N done!" with a **Continue** button.
- Finishing level 10 shows "**You won!**" with a **Play again** button that
  wraps back to level 1.
- The current level is shown as "LVL n" left of the battery HUD.

## Level table

Lives in `App/Levels.swift` (`LevelConfig.all`); `GameScene.startGame(level:)`
picks the config. Map is `mapScale`× screens per dimension.

| Lvl | Map | Runners | Shooters | Rocks | Mirrors | Battery drops | Map spares |
|----|-----|---------|----------|-------|---------|---------------|------------|
| 1  | 1×1 | 1  | 0  | 0  | 0  | 0 | 0 |
| 2  | 1×1 | 3  | 0  | 0  | 0  | 0 | 0 |
| 3  | 1×1 | 3  | 1  | 3  | 0  | 0 | 0 |
| 4  | 2×2 | 4  | 2  | 6  | 0  | 1 | 0 |
| 5  | 2×2 | 5  | 3  | 8  | 3  | 1 | 1 |
| 6  | 2×2 | 6  | 5  | 11 | 5  | 2 | 1 |
| 7  | 3×3 | 8  | 8  | 16 | 8  | 2 | 2 | ← original game
| 8  | 3×3 | 10 | 10 | 18 | 10 | 2 | 2 |
| 9  | 4×4 | 12 | 12 | 24 | 12 | 3 | 2 |
| 10 | 4×4 | 15 | 14 | 28 | 14 | 3 | 3 |

Mechanic introductions: runners (1), shooter + rocks as its hiding cover (3,
the no-line-of-sight spawn rule keeps it hidden), bigger map + battery-carrying
shooters (4), mirrors + map spares (5).

## Notes

- Spawn distances are per-level (`runner/shooterMinPlayerDistance`): the
  original 520pt runner minimum doesn't fit a 1×1 screen, so small maps use
  260/220pt, scaling back up with map size.
- Litter density is constant per screen of map area (`litterPerScreen = 22`,
  ≈ the original 200 on 3×3).
- Battery capacity is unchanged (2s) and refills at the start of every level.
- Levels with shooters always have rocks (shooters spawn beside rocks).
- All changes are app-layer; the engine is untouched (70 tests still pass).
