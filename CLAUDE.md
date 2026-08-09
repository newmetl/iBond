# Laser Taser (repo: iBond)

2D twin-stick stealth shooter for iOS. SwiftUI + SpriteKit app on top of a
pure-Swift custom physics/raycast engine. Rebuilt from scratch in 2026 from a
2011 idea; the repo name stays `iBond`, the game is called **Laser Taser**.

## Repo layout

- `Packages/GameEngine/` — pure Swift engine package, ZERO UIKit/SpriteKit
  imports, fully unit-tested (82 tests). Vector2 (SIMD2<Double> typealias),
  CircleBody (player/npc/rock/shooter/runner kinds), World (fixed-timestep
  update, circle & segment collisions, laser raycast with mirror reflection,
  line-of-sight), Rect, Laser.swift (LaserHit/Mirror/LaserPath + castLaserPath).
- `App/` — app layer. `GameScene.swift` (~900 lines: world building, camera,
  input, all gameplay systems, HUD, effects), `Levels.swift` (BatteryType
  red/orange/white with fixed capacity+power, EnemyTiers I–III, BossStats,
  and LevelConfig: an explicit 50-row level table, boss every 10th level;
  level 0 = dev hunter test), `iBondApp.swift`
  (SwiftUI shell + menu/playing/finished/gameOver overlay state machine, level
  progression persisted via @AppStorage "currentLevel"), `TouchController.swift`
  (touch role assignment by start zone), `SoundManager.swift` + `Sounds/*.wav`
  (AVFoundation loops/one-shots; WAVs synthesized by `tools/generate_sounds.py`),
  `Assets.xcassets` (AppIcon).
- `project.yml` — XcodeGen spec; `iBond.xcodeproj` is GENERATED and gitignored.
- `docs/superpowers/specs/` — design docs per milestone + current-state doc.
  `docs/superpowers/plans/` — the milestone-1 implementation plan.

## Commands

```bash
xcodegen                                     # regenerate iBond.xcodeproj (after project.yml changes / fresh clone)
swift test --package-path Packages/GameEngine  # engine tests (no simulator needed) — expect 82 passing
xcodebuild -project iBond.xcodeproj -scheme iBond \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData build         # simulator build
```

Deploy to Wojtek's iPhone ("iPhone von Adalbert", device id
`C3A2910A-B2BA-57B7-9A72-A21E30126499`, team `M9Z96Z4CSK`, bundle id
`com.wojtekgorecki.iBond`):

```bash
xcodebuild -project iBond.xcodeproj -scheme iBond \
  -destination 'platform=iOS,id=C3A2910A-B2BA-57B7-9A72-A21E30126499' \
  -derivedDataPath DerivedData -allowProvisioningUpdates build
xcrun devicectl device install app --device C3A2910A-B2BA-57B7-9A72-A21E30126499 \
  DerivedData/Build/Products/Debug-iphoneos/iBond.app
xcrun devicectl device process launch --device C3A2910A-B2BA-57B7-9A72-A21E30126499 \
  com.wojtekgorecki.iBond
```

- Free personal team: the install EXPIRES after ~7 days; rebuild+reinstall fixes it.
- Launch sometimes fails right after install (old instance still terminating) —
  wait 2s and retry once. "Locked" error means the phone must be unlocked.

## Working conventions (established with Wojtek)

- One feature branch per change (even one-liners), verify, merge to `master`,
  push to origin, then build+install+launch on the iPhone. He playtests there
  and sends rapid follow-up tuning requests.
- Engine changes are TDD: failing test first in `Packages/GameEngine/Tests/`.
  App-layer changes are verified live in the simulator (see below).
- KISS: he prefers the lowest-effort correct approach; ask one compact design
  question (AskUserQuestion) for real decisions, then move.
- Commit style: `feat(app):` / `fix(engine,app):` / `tune(app):` / `style:` /
  `chore:` with a short body explaining why.

## Simulator verification toolkit

- Since 2026-08-09: Wojtek playtests every change himself on device — a clean
  build + deploy is sufficient verification for app-layer changes. Skip
  simulator staging patches, injected-gesture tests, and video/frame checks
  unless he explicitly asks for them.

- iOS Simulator MCP tools: launch/tap/touch_path/touch2_path/screenshot.
  Injected gestures have 1–3s latency and touch2_path delivers discrete
  press/release pairs (role assignment can flip per pair) — timed screenshots
  race the gesture; expect misses.
- For transient visuals (beam fades, effects): record with
  `xcrun simctl io booted recordVideo` in a background shell, then extract
  frames with the AVFoundation script pattern (see git history / scratchpad
  `extract_frames.swift`: AVAssetImageGenerator at 0.1–0.25s steps, ranks
  frames by red-pixel count to find beam activity).
- To stage rare states (win screen), temporarily patch enemy placement in
  `ensureWorld` to a single runner at `playerStart + Vector2(250, 0)`,
  verify, then restore (keep a .bak; never commit the patch).

## Architecture notes

- Coordinates: SpriteKit bottom-left origin, points; engine world == scene
  coords 1:1. Map is `mapScale`(3)× screen per dimension; SKCameraNode follows
  inside an asymmetric margin box (bottom edge = screen center line) clamped to
  the map. HUD/controls are children of the camera.
- Fixed timestep 1/120 via accumulator in `GameScene.update`; laser cast +
  gameplay checks run once per rendered frame after physics.
- zPosition tiers: litter −2, beam −1, shooter aim −0.5, world circles 0,
  cross/pickups 0.5, player 1, shooter kill beam 1.5, celebration 2.5, spark 2,
  HUD 3 (on camera).
- Engine ordering per step: seekPlayer/steerRunners → integrate →
  resolveCollisions → mirrors → damping → clamp → resolve → mirrors → clamp
  (frames always end in-bounds; tiny transient overlaps heal next frame).
- `playerControlVelocity` (joystick) overrides `moveTarget` (legacy tap-to-move,
  engine-only now, still tested).
- Game rules and non-level tuning constants: top of `GameScene.swift`.
  Per-level composition (map scale, per-tier enemy counts, obstacles, typed
  battery spares/carriers) plus tier/battery/boss stats: `App/Levels.swift`.
  Kill model: shield seconds ÷ battery power; white pierces everything.
  Death retries the same level; finishing level 50 wraps to level 1.
  Design docs: `2026-08-09-tiers-batteries-bosses-plan.md` and
  `docs/superpowers/specs/2026-08-08-laser-taser-current-state.md`.

## Known seams / deferred work

- Laser cast runs at render rate (not inside the fixed step): kills of moving
  runners are mildly framerate-dependent. Fine at 60fps; move the cast into the
  fixed-step loop if it ever matters.
- Runners steer straight-line only — they stall head-on behind rocks/mirrors
  (reads as "taking cover"). Wall-slide or pathfinding is the next AI step.
- Aiming = facing = last movement direction; precise standing aim means nudging
  the stick. Aim-assist was floated but never requested.
- If the player drains the battery with no spares left anywhere, remaining
  enemies are unkillable (accepted by design — runners will end it).
- Spec-doc drift: early docs name `castRay(from:through:)`; code is
  `castLaser(through:)` / `castLaserPath(through:)`.
