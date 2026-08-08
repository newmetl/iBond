import CoreGraphics

/// Per-level tuning: map size and everything that populates it.
///
/// Difficulty ramps by introducing one mechanic at a time — runners only (1),
/// more runners (2), a hidden shooter with its rock cover (3), a bigger map
/// plus battery-carrying shooters (4), mirrors and map spares (5) — then
/// piling on. Level 7 is calibrated to match the original pre-levels game
/// exactly. Spawn distances shrink on small maps where the original minimums
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

    static let all: [LevelConfig] = [
        // 1: one runner on one screen — learn to steer and fire.
        LevelConfig(mapScale: 1, runnerCount: 1, shooterCount: 0,
                    rockCount: 0, mirrorCount: 0,
                    batteryDropCount: 0, initialSpareBatteryCount: 0,
                    runnerMinPlayerDistance: 260, shooterMinPlayerDistance: 220),
        // 2: three runners, still nowhere to hide.
        LevelConfig(mapScale: 1, runnerCount: 3, shooterCount: 0,
                    rockCount: 0, mirrorCount: 0,
                    batteryDropCount: 0, initialSpareBatteryCount: 0,
                    runnerMinPlayerDistance: 260, shooterMinPlayerDistance: 220),
        // 3: first shooter, hidden behind the first rocks.
        LevelConfig(mapScale: 1, runnerCount: 3, shooterCount: 1,
                    rockCount: 3, mirrorCount: 0,
                    batteryDropCount: 0, initialSpareBatteryCount: 0,
                    runnerMinPlayerDistance: 260, shooterMinPlayerDistance: 220),
        // 4: the map opens up; first battery-carrying shooter.
        LevelConfig(mapScale: 2, runnerCount: 4, shooterCount: 2,
                    rockCount: 6, mirrorCount: 0,
                    batteryDropCount: 1, initialSpareBatteryCount: 0,
                    runnerMinPlayerDistance: 420, shooterMinPlayerDistance: 300),
        // 5: mirrors appear (bounce shots, self-hit risk); first map spare.
        LevelConfig(mapScale: 2, runnerCount: 5, shooterCount: 3,
                    rockCount: 8, mirrorCount: 3,
                    batteryDropCount: 1, initialSpareBatteryCount: 1,
                    runnerMinPlayerDistance: 420, shooterMinPlayerDistance: 300),
        LevelConfig(mapScale: 2, runnerCount: 6, shooterCount: 5,
                    rockCount: 11, mirrorCount: 5,
                    batteryDropCount: 2, initialSpareBatteryCount: 1,
                    runnerMinPlayerDistance: 480, shooterMinPlayerDistance: 300),
        // 7: the original game.
        LevelConfig(mapScale: 3, runnerCount: 8, shooterCount: 8,
                    rockCount: 16, mirrorCount: 8,
                    batteryDropCount: 2, initialSpareBatteryCount: 2,
                    runnerMinPlayerDistance: 520, shooterMinPlayerDistance: 300),
        LevelConfig(mapScale: 3, runnerCount: 10, shooterCount: 10,
                    rockCount: 18, mirrorCount: 10,
                    batteryDropCount: 2, initialSpareBatteryCount: 2,
                    runnerMinPlayerDistance: 520, shooterMinPlayerDistance: 300),
        LevelConfig(mapScale: 4, runnerCount: 12, shooterCount: 12,
                    rockCount: 24, mirrorCount: 12,
                    batteryDropCount: 3, initialSpareBatteryCount: 2,
                    runnerMinPlayerDistance: 560, shooterMinPlayerDistance: 320),
        // 10: the gauntlet.
        LevelConfig(mapScale: 4, runnerCount: 15, shooterCount: 14,
                    rockCount: 28, mirrorCount: 14,
                    batteryDropCount: 3, initialSpareBatteryCount: 3,
                    runnerMinPlayerDistance: 560, shooterMinPlayerDistance: 320),
    ]

    static var count: Int { all.count }

    /// Levels are 1-based; out-of-range values clamp to the nearest level.
    static func forLevel(_ level: Int) -> LevelConfig {
        all[max(1, min(level, all.count)) - 1]
    }
}
