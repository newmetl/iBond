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

## Difficulty axes (added same day)

Four per-level axes tighten continuously (Wojtek's request; battery originally
30s → 1s, retuned same day to 10s, then 5s → 1s — long batteries trivialized early levels):

| Lvl | Battery (s) | Runner speed | Telegraph (s) | Rocks/Mirrors |
|----|------|-----|-----|--------|
| 1  | 5    | 110 | 2.5 | 0 / 0  |
| 2  | 4.2  | 120 | 2.3 | 0 / 0  |
| 3  | 3.5  | 130 | 2.1 | 3 / 0  |
| 4  | 2.9  | 140 | 1.9 | 6 / 0  |
| 5  | 2.4  | 150 | 1.7 | 9 / 2  |
| 6  | 2    | 160 | 1.6 | 11 / 5 |
| 7  | 1.7  | 170 | 1.5 | 16 / 8 |
| 8  | 1.4  | 185 | 1.3 | 16 / 12 |
| 9  | 1.2  | 205 | 1.1 | 18 / 18 |
| 10 | 1    | 225 | 0.9 | 16 / 26 |

Level 7 keeps the original constants (170 runner speed, 1.5s telegraph);
player speed stays 320. The mirror share of obstacles grows from 0% to ~60%
(mirrors punish stray shots). `World.runnerSpeed` was already a public engine
var, so all axes are app-layer.

## 20 levels via interpolation (added same day)

The game now has **20 levels**. The 10 hand-tuned rows above became **anchor
rows**: level 1 = anchor 1, level 20 = anchor 10, and every attribute (map
scale included, so maps grow through fractional sizes like 1.37× screens) is
linearly interpolated between neighboring anchors; integer counts round, and
battery drops clamp to the shooter count. Tuning an anchor reshapes the curve
around it. The original pre-levels game (anchor 7) now sits at ≈ level 14.
Generated table (from `LevelConfig.forLevel`):

```
Lvl  map  run  sho  rock mirr drop spare  batt  speed  tele
  1  1.00    1    0     0    0    0     0    5.0    110  2.50
  5  1.00    3    1     3    0    0     0    3.6    129  2.12
 10  2.00    5    4    10    3    1     1    2.3    153  1.67
 14  3.00    8    8    16    9    2     2    1.7    172  1.47
 20  4.00   15   14    16   26    3     3    1.0    225  0.90
```

## Dev menu

A translucent wrench icon (top-right) on every overlay (menu/finished/game
over) toggles a 1–10 level grid; picking a level jumps straight into it and
persists it as `currentLevel`. Ships in the release build (accepted — it's a
hobby game).

## Notes

- Spawn distances are per-level (`runner/shooterMinPlayerDistance`): the
  original 520pt runner minimum doesn't fit a 1×1 screen, so small maps use
  260/220pt, scaling back up with map size.
- Litter density is constant per screen of map area (`litterPerScreen = 22`,
  ≈ the original 200 on 3×3).
- Battery capacity is unchanged (2s) and refills at the start of every level.
- Levels with shooters always have rocks (shooters spawn beside rocks).
- All changes are app-layer; the engine is untouched (70 tests still pass).
