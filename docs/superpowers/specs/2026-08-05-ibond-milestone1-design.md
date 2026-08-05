# iBond Rebuild — Milestone 1 Design

**Date:** 2026-08-05
**Status:** Approved by Wojtek

## Background

iBond was a 2D laser shooter sketched in 2011. The original code was never pushed; the
repo contained only an empty MacRuby template (now removed — see git history). This
document specifies the from-scratch rebuild with a modern iOS stack, based on the
author's description of the original game.

### The original game (full vision, for context)

- The player is a circle with a line showing where the laser gun aims.
- Tap once: the circle moves to that point. Tap and hold: the circle follows the finger.
- While one finger is down, a second touch fires the laser: the beam starts at the
  circle's center and passes through the second finger's position. Holding keeps firing;
  moving the finger sweeps the beam.
- NPC circles move around randomly; when hit by the laser they disappear with a short
  animation.
- A map contains obstacles (rectangles/shapes) that circles cannot pass through and the
  laser cannot shoot through. Laser impacts show a tiny hit animation.
- Custom-written mini physics engine for circle–circle and circle–obstacle collisions.

### Milestone 1 scope (this spec)

- Player circle with aim line; tap-to-move and hold-to-follow movement.
- Two-finger laser firing exactly as described above.
- ~8 NPC circles at random non-overlapping positions. **No NPC movement yet.**
- Circle–circle collision with physical push response (no overlapping/tunneling); the
  player can shove NPCs around by walking into them.
- Laser kills an NPC instantly on contact: scale/fade death animation, then removal.
  Spark effect at the beam's impact point.
- **Out of scope:** obstacles, NPC wandering, score/UI, sound. These are the next
  milestones; the engine seams (raycast, collision resolution) must accommodate them
  without rework.

## Target & Stack

- iOS app, iPhone-first, portrait and landscape.
- Swift; SwiftUI app shell hosting a SpriteKit scene via `SpriteView`.
- **Custom physics engine in pure Swift** (no SpriteKit physics). SpriteKit is used only
  for rendering, animations, and effects.
- Unit tests (XCTest / Swift Testing) for all engine math; TDD.

## Architecture

Three layers with strict dependency direction: Rendering → Engine, Input → Engine.
The engine imports nothing from SpriteKit or UIKit.

### 1. GameEngine (pure Swift, unit-testable)

- **`Vector2`** — 2D vector math built on SIMD (`SIMD2<Double>`): add, scale, length,
  normalize, dot.
- **`CircleBody`** — id, position, velocity, radius, mass, kind (`player` / `npc`).
- **`World`** — owns all bodies plus rectangular bounds (screen size in points).
  - `update(dt:)` with a fixed timestep: integrates velocities, applies player
    target-seeking movement, resolves collisions, clamps bodies to bounds.
  - **Player movement:** the world holds an optional move target; the player moves
    toward it at a constant max speed and stops on arrival. Hold-to-follow simply
    re-sets the target every frame from input.
  - **Collision resolution:** for each overlapping circle pair, separate positionally
    along the center line (weighted by inverse mass) and apply a velocity impulse so
    circles push each other apart realistically and never pass through one another.
  - **Laser raycast:** `castRay(from:through:)` — ray from the player's center through
    the aim point, intersected against every NPC circle; returns the nearest hit
    (body + exact hit point) or the exit point at the world bounds if nothing is hit.
    Pure math; obstacles join the same raycast in a later milestone.
  - **NPC removal:** `remove(bodyID:)` — called when the laser kills an NPC.

### 2. Input layer (two-finger scheme)

Touch handling lives in the SpriteKit scene (`touchesBegan/Moved/Ended/Cancelled`),
tracking touches by identity:

- **First touch down = movement finger.** A quick tap sets a move-to target; holding
  makes the player continuously follow the finger (target re-set on every move event).
- **Any additional touch = laser finger.** While held, the laser fires continuously from
  the player's center through the finger's position; moving the finger sweeps the beam.
- Roles are fixed at touch-down. If the movement finger lifts first, the laser finger
  keeps its role and keeps firing until released; the next new touch becomes the
  movement finger again.

### 3. Rendering (GameScene, SpriteKit)

- Each frame: feed accumulated real time into the engine's fixed-timestep update, then
  mirror engine state into nodes.
- **Player:** circle shape node + aim line showing the most recent laser direction
  (persists after firing stops, matching the original's always-visible gun line).
- **NPCs:** circle shape nodes, one per engine body.
- **Laser:** while firing, a beam from the player's center to the raycast result (hit
  point or bounds exit), with a small spark effect at the impact point.
- **NPC death:** on laser contact the NPC is removed from the engine immediately; the
  scene plays a quick scale/fade-out on its node, then removes the node.

## Data flow

Touches → input state (movement target, laser aim point) → engine `update(dt:)` →
raycast → render sync → animations.

## Error handling & edge cases

- Random NPC placement rejects positions overlapping other bodies (retry sampling).
- Collision resolution must handle the exactly-concentric degenerate case (pick an
  arbitrary separation axis).
- Ray–circle intersection must ignore hits behind the ray origin and handle the aim
  point being inside the player circle (beam still points through it).
- Device rotation resizes the world bounds; bodies re-clamp on the next update.
- Touch bookkeeping must survive `touchesCancelled` (system gestures, calls).

## Testing

- **Unit tests (engine):** vector math; collision separation and impulse (two circles,
  mass-weighted, concentric case); bounds clamping; player target-seeking (moves toward
  target, stops on arrival); ray–circle intersection (hit, miss, nearest-of-many,
  behind-origin, bounds exit).
- **Manual (simulator/device):** two-finger input scheme, rendering, animations.

## Future milestones (not in scope, informing seams)

1. Obstacles: rect/shape bodies that block movement (circle–rect collision) and the
   laser (ray–rect intersection joins the raycast).
2. NPC wandering: random-walk steering for NPC bodies.
3. Polish: score, sound, difficulty, game states.
