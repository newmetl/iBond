# Tiered enemies, typed batteries, bosses — level plan

Date: 2026-08-09
Status: PROPOSAL — awaiting Wojtek's approval; nothing implemented yet.

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

## Introduction schedule (20 levels)

| Lvl | Introduces | Notes |
|----|-----------|-------|
| 1 | Runner I | 2 runners, 1×1 map |
| 2 | — | 4× Runner I |
| 3 | Shooter I + rocks | hidden ambusher |
| 4 | 2×2 map, Red spare | |
| 5 | Mirrors, Runner II | first shield |
| 6 | Hunter I | solo showcase + light escort |
| 7 | Orange battery, Shooter II | counter to shields arrives |
| 8 | — | mixed fight, 2 hunters |
| 9 | 3×3 map, Runner III | |
| 10 | BOSS: Warden | small escort; Orange guaranteed in arena |
| 11 | — | tier II standard |
| 12 | Hunter II | |
| 13 | Shooter III | |
| 14 | White battery | mirror-dense map |
| 15 | 4×4 map | Runner III packs + Hunter II |
| 16 | — | shield-heavy; Orange default, 1 White |
| 17 | Hunter III | |
| 18 | — | all tier III |
| 19 | — | gauntlet, max counts |
| 20 | BOSS: Warden Prime | placeholder until a new boss design |

Battery economy: 1–6 Red only; 7–13 Red common + Orange occasional;
14–20 Orange common, White rare and deliberately placed (guarded).

## Implementation consequences (when approved)

- `Levels.swift` moves from 10 interpolated anchors to an explicit 20-row
  table: per-tier enemy counts + a typed battery list per level (tier
  composition is not interpolatable).
- Shield/armor generalizes the hunter damage accumulator to all enemies;
  battery power multiplies the per-frame damage.
- White beam: separate cast (straight segment, ignores rocks/mirrors,
  collects every hostile crossed).
- Boss = hunter state machine with per-body parameter overrides + size.
- Battery pickups get types (color + HUD tint).

## Open questions for Wojtek

1. Bosses at 10 and 20 — or first boss earlier?
2. White piercing enemies too (multi-kill along the line): keep or drop?
3. All numbers are starting points for on-device tuning.
