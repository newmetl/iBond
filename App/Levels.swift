import CoreGraphics

/// Per-level tuning: map size and everything that populates it.
///
/// The game has 20 levels, interpolated from the 10 hand-tuned anchor rows
/// below (every attribute lerps between neighboring anchors; integer counts
/// round). Anchor 1 is level 1 and anchor 10 is level 20, so tuning an anchor
/// reshapes the curve around it. Difficulty ramps by introducing one mechanic
/// at a time — runners only, then a hidden shooter with its rock cover, then
/// a growing map plus battery-carrying shooters, then mirrors and map spares —
/// then piling on. On top of the counts, four axes tighten continuously:
/// battery capacity 10s → 1s, runner speed 110 → 225 (player moves at 320),
/// shooter aim telegraph 2.5s → 0.9s, and the mirror share of obstacles
/// 0% → ~60% (mirrors punish stray shots, so more mirrors = harder).
/// Anchor 7 (≈ level 13–14) matches the original pre-levels game.
/// Spawn distances shrink on small maps where the original minimums
/// wouldn't fit on a single screen.
struct LevelConfig {
    /// The map spans this many screens in each dimension.
    let mapScale: CGFloat
    let runnerCount: Int
    let shooterCount: Int
    let rockCount: Int
    let mirrorCount: Int
    /// Shooters that drop a spare battery when killed.
    let batteryDropCount: Int
    /// Spare batteries lying on the map from the start.
    let initialSpareBatteryCount: Int
    let runnerMinPlayerDistance: Double
    let shooterMinPlayerDistance: Double
    /// Seconds of laser firing time per battery.
    let laserCapacity: Double
    /// Runner chase speed, points per second.
    let runnerSpeed: Double
    /// Seconds a shooter aims (green telegraph line) before the killing shot.
    let telegraphDuration: Double

    static let anchors: [LevelConfig] = [
        // 1: one runner on one screen — learn to steer and fire.
        LevelConfig(mapScale: 1, runnerCount: 1, shooterCount: 0,
                    rockCount: 0, mirrorCount: 0,
                    batteryDropCount: 0, initialSpareBatteryCount: 0,
                    runnerMinPlayerDistance: 260, shooterMinPlayerDistance: 220,
                    laserCapacity: 10, runnerSpeed: 110, telegraphDuration: 2.5),
        // 2: three runners, still nowhere to hide.
        LevelConfig(mapScale: 1, runnerCount: 3, shooterCount: 0,
                    rockCount: 0, mirrorCount: 0,
                    batteryDropCount: 0, initialSpareBatteryCount: 0,
                    runnerMinPlayerDistance: 260, shooterMinPlayerDistance: 220,
                    laserCapacity: 7.5, runnerSpeed: 120, telegraphDuration: 2.3),
        // 3: first shooter, hidden behind the first rocks.
        LevelConfig(mapScale: 1, runnerCount: 3, shooterCount: 1,
                    rockCount: 3, mirrorCount: 0,
                    batteryDropCount: 0, initialSpareBatteryCount: 0,
                    runnerMinPlayerDistance: 260, shooterMinPlayerDistance: 220,
                    laserCapacity: 6, runnerSpeed: 130, telegraphDuration: 2.1),
        // 4: the map opens up; first battery-carrying shooter.
        LevelConfig(mapScale: 2, runnerCount: 4, shooterCount: 2,
                    rockCount: 6, mirrorCount: 0,
                    batteryDropCount: 1, initialSpareBatteryCount: 0,
                    runnerMinPlayerDistance: 420, shooterMinPlayerDistance: 300,
                    laserCapacity: 4.5, runnerSpeed: 140, telegraphDuration: 1.9),
        // 5: mirrors appear (bounce shots, self-hit risk); first map spare.
        LevelConfig(mapScale: 2, runnerCount: 5, shooterCount: 3,
                    rockCount: 9, mirrorCount: 2,
                    batteryDropCount: 1, initialSpareBatteryCount: 1,
                    runnerMinPlayerDistance: 420, shooterMinPlayerDistance: 300,
                    laserCapacity: 3.5, runnerSpeed: 150, telegraphDuration: 1.7),
        LevelConfig(mapScale: 2, runnerCount: 6, shooterCount: 5,
                    rockCount: 11, mirrorCount: 5,
                    batteryDropCount: 2, initialSpareBatteryCount: 1,
                    runnerMinPlayerDistance: 480, shooterMinPlayerDistance: 300,
                    laserCapacity: 2.8, runnerSpeed: 160, telegraphDuration: 1.6),
        // 7: the original game's counts and axis values.
        LevelConfig(mapScale: 3, runnerCount: 8, shooterCount: 8,
                    rockCount: 16, mirrorCount: 8,
                    batteryDropCount: 2, initialSpareBatteryCount: 2,
                    runnerMinPlayerDistance: 520, shooterMinPlayerDistance: 300,
                    laserCapacity: 2.2, runnerSpeed: 170, telegraphDuration: 1.5),
        LevelConfig(mapScale: 3, runnerCount: 10, shooterCount: 10,
                    rockCount: 16, mirrorCount: 12,
                    batteryDropCount: 2, initialSpareBatteryCount: 2,
                    runnerMinPlayerDistance: 520, shooterMinPlayerDistance: 300,
                    laserCapacity: 1.7, runnerSpeed: 185, telegraphDuration: 1.3),
        LevelConfig(mapScale: 4, runnerCount: 12, shooterCount: 12,
                    rockCount: 18, mirrorCount: 18,
                    batteryDropCount: 3, initialSpareBatteryCount: 2,
                    runnerMinPlayerDistance: 560, shooterMinPlayerDistance: 320,
                    laserCapacity: 1.3, runnerSpeed: 205, telegraphDuration: 1.1),
        // 10: the gauntlet — mirror-heavy, sprinting runners, snap shooters.
        LevelConfig(mapScale: 4, runnerCount: 15, shooterCount: 14,
                    rockCount: 16, mirrorCount: 26,
                    batteryDropCount: 3, initialSpareBatteryCount: 3,
                    runnerMinPlayerDistance: 560, shooterMinPlayerDistance: 320,
                    laserCapacity: 1, runnerSpeed: 225, telegraphDuration: 0.9),
    ]

    static let count = 20

    /// Levels are 1-based; out-of-range values clamp to the nearest level.
    /// Level n maps onto a fractional position along the anchor rows and
    /// every attribute is interpolated between the two neighboring anchors.
    static func forLevel(_ level: Int) -> LevelConfig {
        let clamped = max(1, min(level, count))
        let position = Double(clamped - 1) / Double(count - 1) * Double(anchors.count - 1)
        let below = Int(position.rounded(.down))
        let above = min(below + 1, anchors.count - 1)
        return interpolate(anchors[below], anchors[above], t: position - Double(below))
    }

    private static func interpolate(_ a: LevelConfig, _ b: LevelConfig,
                                    t: Double) -> LevelConfig {
        func lerp(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        func lerp(_ x: Int, _ y: Int) -> Int { Int(lerp(Double(x), Double(y)).rounded()) }
        let shooters = lerp(a.shooterCount, b.shooterCount)
        return LevelConfig(
            mapScale: CGFloat(lerp(Double(a.mapScale), Double(b.mapScale))),
            runnerCount: lerp(a.runnerCount, b.runnerCount),
            shooterCount: shooters,
            rockCount: lerp(a.rockCount, b.rockCount),
            mirrorCount: lerp(a.mirrorCount, b.mirrorCount),
            // Carriers are shooters, so drops can never exceed them.
            batteryDropCount: min(lerp(a.batteryDropCount, b.batteryDropCount), shooters),
            initialSpareBatteryCount: lerp(a.initialSpareBatteryCount,
                                           b.initialSpareBatteryCount),
            runnerMinPlayerDistance: lerp(a.runnerMinPlayerDistance,
                                          b.runnerMinPlayerDistance),
            shooterMinPlayerDistance: lerp(a.shooterMinPlayerDistance,
                                           b.shooterMinPlayerDistance),
            laserCapacity: lerp(a.laserCapacity, b.laserCapacity),
            runnerSpeed: lerp(a.runnerSpeed, b.runnerSpeed),
            telegraphDuration: lerp(a.telegraphDuration, b.telegraphDuration))
    }
}
