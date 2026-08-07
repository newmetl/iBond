# iBond Milestone 2 — Rocks & Mirrors

**Date:** 2026-08-08
**Status:** Approved by Wojtek (rapid-iteration flow)

## Scope

- **Rocks**: 3 immovable obstacles, mid-map. Block circles (player and NPCs
  cannot pass; off-center approaches slide around) and absorb the laser.
- **Mirrors**: 2 reflective line segments, mid-map. The laser reflects off them
  (up to 5 bounces) enabling bank shots at NPCs hidden behind rocks; circles
  cannot pass through mirrors either.
- Spawn placement never puts NPCs/rocks on rocks or mirrors; placement order is
  player → mirrors → rocks → NPCs, each pass avoiding everything before it.
- Random layout per game; also: beam fade-out lengthened to 500ms.

## Engine design

- `CircleBody.Kind` gains `.rock`; `isStatic` bodies skip integration, damping,
  and bounds clamping, and have zero inverse mass in collision resolution
  (partner takes the full separation/impulse).
- `Mirror { start, end }` segments stored on `World` (`addMirror(from:to:)`).
- `castLaserPath(through:) -> LaserPath { points, bodyID }` — multi-bounce ray:
  nearest of body hit vs mirror hit each leg; mirrors reflect `d − 2(d·n)n`;
  capped at `World.maxLaserBounces = 5`; `castLaser` remains as the single-hit
  view (final endpoint + struck body).
- `raySegmentIntersection` (Cramer solve, t > ε, s ∈ [0,1]) and
  `closestPoint(onSegment:)` support the raycast and circle-vs-segment
  collision (`resolveMirrorCollisions`: positional push-out + approach-velocity
  cancellation, run in both resolution passes).
- `randomFreePosition(radius:in:using:)` adds a `Rect` region constraint and
  now also keeps clear of mirrors.

## App design

- Layout in `GameScene.ensureWorld` (middle region = x 15–85%, y 28–72%).
- Rocks render as irregular 9-vertex polygons tracing the collider circle;
  mirrors as light-blue rounded lines with a slight glow.
- The beam renders `LaserPath.points` as a polyline; spark sits at the final
  point; aim rotation uses the first segment; only `.npc` hits kill.

## Verification

- 54 engine unit tests (13 new: rocks, mirrors, reflection, bank shot behind a
  rock, bounce cap, segment collision, spawn avoidance, region sampling).
- Simulator: reflection observed on video (beam bends at mirror, spark at
  wall); slide-around-rock blocking observed; spawn placement clean across
  multiple games; battery/game-over flows intact in M2 worlds.
