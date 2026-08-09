# Tiered enemies, typed batteries, bosses — level plan

Date: 2026-08-09
Status: approved by Wojtek (white pierces everything) and implemented 2026-08-09.

## Core mechanic change

Difficulty stops coming from shrinking battery capacity (that scaling is
removed). Instead every enemy gets a **shield** measured in seconds-of-red-beam
and every battery type a **power multiplier**; kill time = shield ÷ power.
The ramp comes from enemy tier mix, counts, map size, and which battery types
a level supplies.

## Batteries (fixed stats, never scale with level)

| Type | Capacity | Power | Special |
|------|----------|-------|---------|
| Red | 3.0s | 1× | today's laser (pickup recolored from green) |
| Orange | 2.0s | 2× | kills twice as fast |
| White | 1.0s | 4× | penetrates rocks and mirrors (straight line, no reflection, no self-hit); suggestion: kills every enemy along the line |

- Picking up a battery overwrites the remaining charge AND type (a Red pickup
  while holding a half White is a downgrade — deliberate strategy element).
- Every level starts with a full Red.

## Enemy tiers

| | Tier I | Tier II | Tier III |
|---|---|---|---|
| Runner speed / shield | 130 / 0 | 170 / 0.2s | 210 / 0.45s |
| Shooter aim / shield | 2.2s / 0 | 1.6s / 0.25s | 1.1s / 0.5s |
| Hunter approach / aim / shield | 190 / 0.6s / 0.3s | 210 / 0.5s / 0.6s | 230 / 0.4s / 1.0s |

Hunter patrol speed stays 55 across tiers. Player speed stays 320.
Tier visuals: pips or brightness steps on the body color (TBD at build time).

**Boss: Warden** (first boss; hunter behavior): 3× size (42pt radius),
patrol 35, approach 100, aim 0.8s, shield 4.0s. Boss math: Red alone (3s)
can't finish it — forces a battery grab mid-fight; exactly one full Orange;
1s of White. More bosses later (slots at levels 10 and 20).

## Battery sourcing rules

- Runners never drop anything (pure threat).
- Shooters: designated carriers drop RED — 1 carrier from L5, 2 from L7,
  3 from L34.
- Hunters: designated carriers drop ORANGE from L13 — 1, 2 from L18,
  3 from L38.
- WHITE exists only in boss fights FROM LEVEL 30 (Wojtek, same day):
  pre-placed arena pickup(s), 1 at L30, 2 from L40. Orange debuts in the
  L10 boss arena (2 spares there; L20's arena carries 2 Orange too). Never dropped, never on regular maps. The boss itself
  drops nothing; its escort follows normal carrier rules.
- Map spares: Red tapers off (0 from L46); Orange appears L13 and grows to 5.
- Every level starts with a full Red; pickups overwrite type + charge.

## 50-level table (boss every 10th; same Warden for now)

R/S/H tiers = counts; Red/Org/Wht = map-spare pickups; S→R / H→O = carrier
drop counts. Boss arenas are deliberately small.

| Lvl | Map | R1 | R2 | R3 | S1 | S2 | S3 | H1 | H2 | H3 | Boss | Rocks | Mirr | Red | Org | Wht | S→R | H→O |
|----|-----|----|----|----|----|----|----|----|----|----|------|------|------|-----|-----|-----|-----|-----|
| 1 | 1.0 | 2 | – | – | – | – | – | – | – | – | – | 0 | 0 | – | – | – | – | – |
| 2 | 1.0 | 4 | – | – | – | – | – | – | – | – | – | 0 | 0 | – | – | – | – | – |
| 3 | 1.0 | 3 | – | – | 1 | – | – | – | – | – | – | 3 | 0 | – | – | – | – | – |
| 4 | 1.5 | 4 | – | – | 2 | – | – | – | – | – | – | 5 | 0 | 1 | – | – | – | – |
| 5 | 1.5 | 5 | – | – | 2 | – | – | – | – | – | – | 6 | 0 | 1 | – | – | 1 | – |
| 6 | 2.0 | 5 | – | – | 3 | – | – | – | – | – | – | 8 | 2 | 1 | – | – | 1 | – |
| 7 | 2.0 | 6 | – | – | 3 | – | – | – | – | – | – | 9 | 3 | 1 | – | – | 2 | – |
| 8 | 2.0 | 4 | 2 | – | 3 | – | – | – | – | – | – | 10 | 3 | 1 | – | – | 2 | – |
| 9 | 2.0 | 4 | 3 | – | 4 | – | – | – | – | – | – | 11 | 4 | 1 | – | – | 2 | – |
| 10 | 2.0 | 2 | – | – | – | – | – | – | – | – | W | 6 | 3 | 1 | 2 | – | – | – |
| 11 | 2.0 | 4 | 2 | – | 3 | – | – | 1 | – | – | – | 10 | 4 | 1 | – | – | 2 | – |
| 12 | 2.5 | 4 | 3 | – | 3 | – | – | 1 | – | – | – | 12 | 5 | 1 | – | – | 2 | – |
| 13 | 2.5 | 4 | 3 | – | 3 | – | – | 2 | – | – | – | 12 | 5 | 1 | 1 | – | 2 | 1 |
| 14 | 2.5 | 5 | 3 | – | 4 | – | – | 2 | – | – | – | 13 | 6 | 1 | 1 | – | 2 | 1 |
| 15 | 2.5 | 4 | 4 | – | 2 | 2 | – | 2 | – | – | – | 13 | 6 | 1 | 1 | – | 2 | 1 |
| 16 | 3.0 | 4 | 4 | – | 2 | 2 | – | 3 | – | – | – | 14 | 7 | 2 | 1 | – | 2 | 1 |
| 17 | 3.0 | 4 | 5 | – | 2 | 3 | – | 3 | – | – | – | 14 | 7 | 2 | 1 | – | 2 | 1 |
| 18 | 3.0 | 3 | 6 | – | 2 | 3 | – | 3 | – | – | – | 15 | 8 | 2 | 1 | – | 2 | 2 |
| 19 | 3.0 | 3 | 6 | – | 2 | 4 | – | 4 | – | – | – | 15 | 8 | 2 | 1 | – | 2 | 2 |
| 20 | 2.0 | – | 3 | – | – | – | – | 1 | – | – | W | 6 | 4 | – | 2 | – | – | 1 |
| 21 | 3.0 | 3 | 5 | – | 2 | 4 | – | 3 | – | – | – | 15 | 8 | 2 | 1 | – | 2 | 1 |
| 22 | 3.0 | 3 | 4 | 2 | 2 | 4 | – | 3 | – | – | – | 16 | 8 | 2 | 1 | – | 2 | 1 |
| 23 | 3.0 | 2 | 5 | 2 | 2 | 4 | – | 3 | – | – | – | 16 | 9 | 2 | 1 | – | 2 | 1 |
| 24 | 3.0 | 2 | 5 | 3 | 2 | 4 | – | 2 | 1 | – | – | 16 | 9 | 2 | 2 | – | 2 | 2 |
| 25 | 3.0 | 2 | 5 | 3 | 2 | 5 | – | 2 | 2 | – | – | 17 | 9 | 2 | 2 | – | 2 | 2 |
| 26 | 3.5 | 2 | 5 | 4 | 2 | 5 | – | 2 | 2 | – | – | 17 | 10 | 2 | 2 | – | 2 | 2 |
| 27 | 3.5 | 2 | 4 | 5 | 1 | 5 | 1 | 2 | 2 | – | – | 18 | 10 | 2 | 2 | – | 2 | 2 |
| 28 | 3.5 | 1 | 5 | 5 | 1 | 5 | 2 | 2 | 3 | – | – | 18 | 11 | 2 | 2 | – | 2 | 2 |
| 29 | 3.5 | 1 | 5 | 6 | 1 | 5 | 2 | 2 | 3 | – | – | 18 | 11 | 2 | 2 | – | 2 | 2 |
| 30 | 2.5 | – | – | 4 | – | – | – | – | 2 | – | W | 7 | 5 | – | 2 | 1 | – | 2 |
| 31 | 3.5 | – | 6 | 4 | – | 5 | 2 | 1 | 3 | – | – | 18 | 11 | 2 | 2 | – | 2 | 2 |
| 32 | 3.5 | – | 6 | 5 | – | 5 | 3 | 1 | 3 | – | – | 19 | 12 | 2 | 2 | – | 2 | 2 |
| 33 | 3.5 | – | 5 | 6 | – | 5 | 3 | – | 3 | 1 | – | 19 | 12 | 1 | 2 | – | 2 | 2 |
| 34 | 4.0 | – | 5 | 6 | – | 4 | 4 | – | 3 | 1 | – | 20 | 13 | 1 | 3 | – | 3 | 2 |
| 35 | 4.0 | – | 5 | 7 | – | 4 | 4 | – | 3 | 2 | – | 20 | 13 | 1 | 3 | – | 3 | 2 |
| 36 | 4.0 | – | 4 | 8 | – | 4 | 5 | – | 2 | 3 | – | 20 | 14 | 1 | 3 | – | 3 | 2 |
| 37 | 4.0 | – | 4 | 8 | – | 3 | 6 | – | 2 | 3 | – | 21 | 14 | 1 | 3 | – | 3 | 2 |
| 38 | 4.0 | – | 3 | 9 | – | 3 | 6 | – | 2 | 4 | – | 21 | 15 | 1 | 3 | – | 3 | 3 |
| 39 | 4.0 | – | 3 | 10 | – | 3 | 7 | – | 2 | 4 | – | 22 | 15 | 1 | 3 | – | 3 | 3 |
| 40 | 3.0 | – | – | 5 | – | – | – | – | – | 3 | W | 8 | 6 | – | 2 | 2 | – | 3 |
| 41 | 4.0 | – | 2 | 10 | – | 2 | 7 | – | 1 | 5 | – | 22 | 15 | 1 | 3 | – | 3 | 3 |
| 42 | 4.0 | – | 2 | 11 | – | 2 | 8 | – | 1 | 5 | – | 22 | 16 | 1 | 3 | – | 3 | 3 |
| 43 | 4.0 | – | 2 | 11 | – | 2 | 8 | – | – | 6 | – | 23 | 16 | 1 | 4 | – | 3 | 3 |
| 44 | 4.5 | – | 1 | 12 | – | 1 | 9 | – | – | 6 | – | 23 | 17 | 1 | 4 | – | 3 | 3 |
| 45 | 4.5 | – | 1 | 12 | – | 1 | 9 | – | – | 7 | – | 24 | 17 | 1 | 4 | – | 3 | 3 |
| 46 | 4.5 | – | – | 13 | – | – | 10 | – | – | 7 | – | 24 | 18 | – | 4 | – | 3 | 3 |
| 47 | 4.5 | – | – | 14 | – | – | 10 | – | – | 8 | – | 25 | 18 | – | 4 | – | 3 | 3 |
| 48 | 5.0 | – | – | 15 | – | – | 11 | – | – | 8 | – | 25 | 19 | – | 5 | – | 3 | 3 |
| 49 | 5.0 | – | – | 16 | – | – | 12 | – | – | 9 | – | 26 | 19 | – | 5 | – | 3 | 3 |
| 50 | 3.0 | – | – | 6 | – | – | 2 | – | – | 4 | W | 10 | 8 | – | 3 | 2 | – | 3 |

Introduction milestones: Runner I @1 · Shooter I + rocks @3 · Red spares @4 ·
Red carrier drops @5 · mirrors @6 · Runner II @8 · Boss + Orange @10 ·
Hunter I @11 · Orange carriers @13 · Shooter II @15 · Runner III @22 · Hunter II @24 ·
Shooter III @27 · Hunter III @33.

Design shape: breather after every boss; tier mixes rotate downward-tier-out;
maps grow 1.0 → 5.0 screens; boss arenas tight (2.0–3.0). Endgame budget
check (L49): shield mass ≈ 22 red-seconds vs ≈ 44 red-seconds of supply —
the same ~2× comfort ratio as the early game.

## Implementation consequences (when approved)

- `Levels.swift` becomes an explicit 50-row table: per-tier enemy counts,
  rocks/mirrors, typed map spares, typed carrier counts, boss flag.
- Shield/armor generalizes the hunter damage accumulator to all enemies;
  battery power multiplies per-frame damage.
- White beam: straight cast ignoring rocks/mirrors, hitting every hostile
  crossed (suggestion — pending Wojtek's call).
- Boss = hunter state machine with per-body parameter overrides + 3× size.
- Battery pickups get types (color + HUD tint); charge+type overwrite on
  pickup; full Red at level start.

## Open questions for Wojtek

1. White piercing enemies too (multi-kill along the line): keep or drop?
2. All numbers are starting points for on-device tuning.
