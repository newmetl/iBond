# iBond Milestone 3 — Scrolling Map, Shooters, Runners, Pickups

**Date:** 2026-08-08
**Status:** Approved by Wojtek (telegraph 0.6s / 2×2 map / 4+4 enemies with 2 drops)

## Scope

- **Map & camera**: the map is 2×2 screens; an `SKCameraNode` follows the player
  only when they near the screen edge (130pt margin box), clamped to the map.
  ~90 translucent litter shapes (stones/rubbish) make scrolling visible;
  decorative only. The battery HUD rides the camera.
- **Shooters** (4, red): stationary ambushers placed adjacent to rocks, ≥300pt
  from spawn. While on screen AND with line of sight to the player they show a
  thin green aim line for 0.6s, then fire a green beam that kills the player.
  Losing sight (or scrolling off screen) resets the aim. Killable by the laser.
- **Runners** (4, purple): chase the player at 60% player speed (engine
  steering), spawn ≥520pt out; touching the player kills. Killable by the laser.
- **Self-hit**: a reflected beam segment can hit the player — game over.
- **Battery pickups**: 2 shooters carry spares; on death they drop a pulsing
  green battery at their position; walking over it recharges to 100% (2.00s).
- **Win**: eliminate all hostiles. **Lose**: shot, touched, or battery empty.

## Engine

- `Kind` gains `.shooter`/`.runner` (+ `.isHostile` covering `.npc` too);
  damping now applies to all hostiles.
- `steerRunners()` sets runner velocity toward the player each step (before
  integration, so shoves displace but never deflect); no player → stand down.
- `hasLineOfSight(from:to:)` — segment clear of other bodies, rocks, mirrors
  (mirrors block sight, they don't bend it).
- `castLaserPath` includes the player as a hittable body on post-bounce
  segments (first segment still excludes it — the beam starts inside).
- 66 unit tests total (12 new).

## App

- Layout order: player (map center) → mirrors (4) → rocks (8) → shooters (near
  random rocks) → runners (far spawns). Litter scattered at build.
- Shooter state machine (idle/aiming/fired) driven per frame in the scene;
  killPlayer() is the shared death path (removes the body — runners stop —
  plays the grow/fade, then `onPlayerKilled` → Game over overlay).
- Tuning knobs in GameScene: counts, `telegraphDuration`, spawn distances,
  `cameraEdgeMargin`, `mapScale`.

## Verification

- 66 engine tests green; simulator: camera scroll to a map corner observed,
  litter parallax visible, runners chased and killed the player (Game over),
  shooters spawned adjacent to rocks. Bank-shot, LOS, self-hit are
  engine-tested; telegraph timing and pickups verified by code review and
  awaiting on-device playtest.
