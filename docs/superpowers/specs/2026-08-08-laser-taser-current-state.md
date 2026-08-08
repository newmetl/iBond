# Laser Taser — Current State (end of session 2026-08-08)

The authoritative snapshot of game rules and tuning after milestone 3 and the
rapid-iteration rounds that followed it. Supersedes details in the M1–M3 docs
where they conflict. All constants live at the top of `App/GameScene.swift`
unless noted.

## World

- Map: `mapScale = 3` screens per dimension, fixed at game start.
- 16 rocks (r 38–56) and 8 mirrors (length 140) placed in the map inset by
  120pt; 200 translucent litter shapes (decorative only).
- Placement order: player (map center) → mirrors → rocks → shooters → runners →
  2 spare batteries (each pass avoids everything placed before it; spawn
  sampling also keeps clear of mirrors).

## Camera

- SKCameraNode; follow box margins: sides 175, top 280, bottom edge = screen
  center line (moving down scrolls from 50% height). Clamped to map bounds.
- HUD and controls are camera children.

## Player

- Speed 320 pt/s via virtual joystick (lower-left, corner offset (80, 92),
  knob travel 70, capture zone 120, dead zone 8%). Facing follows movement
  (smoothed, ~90% in 150ms); the beam fires along facing.
- Fire button lower-right (corner offset (65, 88), radius 44, zone 100):
  tap = burst, hold = continuous. Map touches do nothing.

## Laser & battery

- Thin crisp red line (1.5pt, no glow), reflects off mirrors up to 5 bounces,
  stops at rocks, kills hostiles instantly (spark burst at the hit point),
  kills the PLAYER if reflected back into them.
- Battery: 2.00s of firing, drains only while the beam renders. Empty ≠ game
  over — firing is just disabled until a spare is collected (full refill,
  green ring + icon pulse effect). Beam fades out over 500ms on release.
- Spares: 2 on the map at start (≥150pt from spawn) + 2 dropped by carrier
  shooters (of 8). HUD: battery icon with color bar (green >55%, yellow >25%,
  red below), no text; enemy dot row below (red = shooters, purple = runners);
  whole HUD at 85% opacity.

## Enemies

- 8 shooters (red, r14): stationary, shoveable, placed adjacent to rocks with
  NO line of sight to the player spawn, ≥300pt away. When on screen AND with
  LOS to the player: green telegraph line for 1.5s, then a green kill beam
  (same thin style as the player's, in green). Losing sight/screen resets aim.
  Facing line always tracks the player.
- 8 runners (purple, r14): spawn ≥520pt out, inert until first on screen, then
  chase forever at 170 pt/s (engine `runnerSpeed`); touch kills the player.
  Facing line follows movement. Blocked by rocks/mirrors (no pathfinding).
- Death animation: grow 1.6× + fade 0.15s; carriers drop a pulsing battery.

## Win / lose

- Win: all hostiles eliminated → firework celebration (6 staggered multicolor
  bursts + rings, 1.6s) → "Done!" overlay with **Restart**.
- Lose: shot by a shooter, touched by a runner, or self-hit by reflection →
  player death animation → "Game over!" overlay with **Restart**.
- Menu shows "Laser Taser" + "Start!". All buttons start a fresh random game.

## Identity

- Display name "Laser Taser" (`INFOPLIST_KEY_CFBundleDisplayName`), app icon in
  `App/Assets.xcassets/AppIcon.appiconset` (generated 1024pt scene: player
  firing into a shooter). Bundle id `com.wojtekgorecki.iBond` unchanged.

## Engine surface (Packages/GameEngine, 70 tests)

`World`: addPlayer/addNPC/addRock/addShooter/addRunner/addMirror,
`playerControlVelocity` (joystick) / `moveTarget` (legacy), `runnerSpeed`,
`activateRunner(_:)`/`activeRunnerIDs`, `update(dt:)`,
`castLaserPath(through:)` → `LaserPath{points, bodyID}` (player hittable after
first bounce), `castLaser(through:)` single-hit view,
`hasLineOfSight(from:to:)` (bodies, rocks, mirrors block),
`randomFreePosition(radius:[in Rect]:using:)` (avoids bodies + mirrors),
`remove`/`setVelocity`/`body(withID:)`/`rockIDs`.
