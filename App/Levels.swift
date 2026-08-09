import CoreGraphics

/// Battery types: fixed stats that never scale with level. Picking one up
/// overwrites both the remaining charge AND the type; every level starts
/// with a full Red. Difficulty comes from the enemy tier mix and the battery
/// economy, not from shrinking capacity.
enum BatteryType: Int, CaseIterable {
    case red    // the classic laser
    case orange // double power: kills shielded enemies twice as fast
    case white  // quadruple power; flies straight through rocks, mirrors,
                // and every enemy on the line (no reflection, no self-hit)

    /// Seconds of firing time when full.
    var capacity: Double { [3.0, 2.0, 1.0][rawValue] }
    /// Damage multiplier vs shields (kill time = shield / power).
    var power: Double { [1.0, 2.0, 4.0][rawValue] }
    var piercing: Bool { self == .white }
}

/// Per-tier enemy attributes; index 0..2 = tier I..III. Shields are seconds
/// of red-beam contact (kill time = shield / battery power; 0 = instant).
enum EnemyTiers {
    static let runnerSpeed = [130.0, 170.0, 210.0]
    static let runnerShield = [0.0, 0.2, 0.45]
    static let shooterAim = [2.2, 1.6, 1.1]
    static let shooterShield = [0.0, 0.25, 0.5]
    static let hunterApproach = [190.0, 210.0, 230.0]
    static let hunterAim = [0.6, 0.5, 0.4]
    static let hunterShield = [0.3, 0.6, 1.0]
}

/// The Warden — every 10th level's boss (more bosses later): hunter behavior
/// at 3× size, slow, massively shielded. Red alone (3s) can't finish it;
/// exactly one full Orange or 1s of White can.
enum BossStats {
    static let radius = 42.0
    static let mass = 9.0
    static let patrolSpeed = 35.0
    static let approachSpeed = 100.0
    static let aimDuration = 0.8
    static let shield = 4.0
}

/// One level's composition. See
/// docs/superpowers/specs/2026-08-09-tiers-batteries-bosses-plan.md for the
/// full design table this encodes.
struct LevelConfig {
    /// The map spans this many screens in each dimension.
    let mapScale: CGFloat
    /// Per-tier counts, index 0..2 = tier I..III.
    let runners: [Int]
    let shooters: [Int]
    let hunters: [Int]
    let bossCount: Int
    let rockCount: Int
    let mirrorCount: Int
    /// Map-spare battery pickups placed at level start.
    let redSpares: Int
    let orangeSpares: Int
    let whiteSpares: Int
    /// Designated carriers: shooters drop Red, hunters drop Orange.
    let shooterRedCarriers: Int
    let hunterOrangeCarriers: Int

    /// Spawn distances derive from the map size (small maps can't honor the
    /// big-map minimums).
    var runnerMinPlayerDistance: Double { min(560, 200 + 120 * Double(mapScale)) }
    var shooterMinPlayerDistance: Double { min(320, 160 + 60 * Double(mapScale)) }

    static let count = 50

    /// Compact row builder: r/s/h are per-tier counts, spares is
    /// [red, orange, white], carriers is [shooter→red, hunter→orange].
    private static func row(_ map: Double, r: [Int], s: [Int], h: [Int],
                            boss: Int = 0, rocks: Int, mirrors: Int,
                            spares: [Int], carriers: [Int]) -> LevelConfig {
        LevelConfig(mapScale: CGFloat(map), runners: r, shooters: s, hunters: h,
                    bossCount: boss, rockCount: rocks, mirrorCount: mirrors,
                    redSpares: spares[0], orangeSpares: spares[1],
                    whiteSpares: spares[2],
                    shooterRedCarriers: carriers[0],
                    hunterOrangeCarriers: carriers[1])
    }

    /// Dev-only hunter proving ground ("level 0" in the dev grid).
    static let hunterTest = row(2.0, r: [0, 0, 0], s: [0, 0, 0], h: [3, 0, 0],
                                rocks: 8, mirrors: 6, spares: [1, 1, 0],
                                carriers: [0, 1])

    /// The 50 levels, straight from the design table: boss every 10th,
    /// breather after each boss, tiers rotating in as lower tiers fade out.
    static let all: [LevelConfig] = [
        row(1.0, r: [2, 0, 0], s: [0, 0, 0], h: [0, 0, 0], rocks: 0, mirrors: 0, spares: [0, 0, 0], carriers: [0, 0]),
        row(1.0, r: [4, 0, 0], s: [0, 0, 0], h: [0, 0, 0], rocks: 0, mirrors: 0, spares: [0, 0, 0], carriers: [0, 0]),
        row(1.0, r: [3, 0, 0], s: [1, 0, 0], h: [0, 0, 0], rocks: 3, mirrors: 0, spares: [0, 0, 0], carriers: [0, 0]),
        row(1.5, r: [4, 0, 0], s: [2, 0, 0], h: [0, 0, 0], rocks: 5, mirrors: 0, spares: [1, 0, 0], carriers: [0, 0]),
        row(1.5, r: [5, 0, 0], s: [2, 0, 0], h: [0, 0, 0], rocks: 6, mirrors: 0, spares: [1, 0, 0], carriers: [1, 0]),
        row(2.0, r: [5, 0, 0], s: [3, 0, 0], h: [0, 0, 0], rocks: 8, mirrors: 2, spares: [1, 0, 0], carriers: [1, 0]),
        row(2.0, r: [6, 0, 0], s: [3, 0, 0], h: [0, 0, 0], rocks: 9, mirrors: 3, spares: [1, 0, 0], carriers: [2, 0]),
        row(2.0, r: [4, 2, 0], s: [3, 0, 0], h: [0, 0, 0], rocks: 10, mirrors: 3, spares: [1, 0, 0], carriers: [2, 0]),
        row(2.0, r: [4, 3, 0], s: [4, 0, 0], h: [0, 0, 0], rocks: 11, mirrors: 4, spares: [1, 0, 0], carriers: [2, 0]),
        row(2.0, r: [2, 0, 0], s: [0, 0, 0], h: [0, 0, 0], boss: 1, rocks: 6, mirrors: 3, spares: [1, 0, 1], carriers: [0, 0]),
        row(2.0, r: [4, 2, 0], s: [3, 0, 0], h: [1, 0, 0], rocks: 10, mirrors: 4, spares: [1, 0, 0], carriers: [2, 0]),
        row(2.5, r: [4, 3, 0], s: [3, 0, 0], h: [1, 0, 0], rocks: 12, mirrors: 5, spares: [1, 0, 0], carriers: [2, 0]),
        row(2.5, r: [4, 3, 0], s: [3, 0, 0], h: [2, 0, 0], rocks: 12, mirrors: 5, spares: [1, 1, 0], carriers: [2, 1]),
        row(2.5, r: [5, 3, 0], s: [4, 0, 0], h: [2, 0, 0], rocks: 13, mirrors: 6, spares: [1, 1, 0], carriers: [2, 1]),
        row(2.5, r: [4, 4, 0], s: [2, 2, 0], h: [2, 0, 0], rocks: 13, mirrors: 6, spares: [1, 1, 0], carriers: [2, 1]),
        row(3.0, r: [4, 4, 0], s: [2, 2, 0], h: [3, 0, 0], rocks: 14, mirrors: 7, spares: [2, 1, 0], carriers: [2, 1]),
        row(3.0, r: [4, 5, 0], s: [2, 3, 0], h: [3, 0, 0], rocks: 14, mirrors: 7, spares: [2, 1, 0], carriers: [2, 1]),
        row(3.0, r: [3, 6, 0], s: [2, 3, 0], h: [3, 0, 0], rocks: 15, mirrors: 8, spares: [2, 1, 0], carriers: [2, 2]),
        row(3.0, r: [3, 6, 0], s: [2, 4, 0], h: [4, 0, 0], rocks: 15, mirrors: 8, spares: [2, 1, 0], carriers: [2, 2]),
        row(2.0, r: [0, 3, 0], s: [0, 0, 0], h: [1, 0, 0], boss: 1, rocks: 6, mirrors: 4, spares: [0, 1, 1], carriers: [0, 1]),
        row(3.0, r: [3, 5, 0], s: [2, 4, 0], h: [3, 0, 0], rocks: 15, mirrors: 8, spares: [2, 1, 0], carriers: [2, 1]),
        row(3.0, r: [3, 4, 2], s: [2, 4, 0], h: [3, 0, 0], rocks: 16, mirrors: 8, spares: [2, 1, 0], carriers: [2, 1]),
        row(3.0, r: [2, 5, 2], s: [2, 4, 0], h: [3, 0, 0], rocks: 16, mirrors: 9, spares: [2, 1, 0], carriers: [2, 1]),
        row(3.0, r: [2, 5, 3], s: [2, 4, 0], h: [2, 1, 0], rocks: 16, mirrors: 9, spares: [2, 2, 0], carriers: [2, 2]),
        row(3.0, r: [2, 5, 3], s: [2, 5, 0], h: [2, 2, 0], rocks: 17, mirrors: 9, spares: [2, 2, 0], carriers: [2, 2]),
        row(3.5, r: [2, 5, 4], s: [2, 5, 0], h: [2, 2, 0], rocks: 17, mirrors: 10, spares: [2, 2, 0], carriers: [2, 2]),
        row(3.5, r: [2, 4, 5], s: [1, 5, 1], h: [2, 2, 0], rocks: 18, mirrors: 10, spares: [2, 2, 0], carriers: [2, 2]),
        row(3.5, r: [1, 5, 5], s: [1, 5, 2], h: [2, 3, 0], rocks: 18, mirrors: 11, spares: [2, 2, 0], carriers: [2, 2]),
        row(3.5, r: [1, 5, 6], s: [1, 5, 2], h: [2, 3, 0], rocks: 18, mirrors: 11, spares: [2, 2, 0], carriers: [2, 2]),
        row(2.5, r: [0, 0, 4], s: [0, 0, 0], h: [0, 2, 0], boss: 1, rocks: 7, mirrors: 5, spares: [0, 2, 1], carriers: [0, 2]),
        row(3.5, r: [0, 6, 4], s: [0, 5, 2], h: [1, 3, 0], rocks: 18, mirrors: 11, spares: [2, 2, 0], carriers: [2, 2]),
        row(3.5, r: [0, 6, 5], s: [0, 5, 3], h: [1, 3, 0], rocks: 19, mirrors: 12, spares: [2, 2, 0], carriers: [2, 2]),
        row(3.5, r: [0, 5, 6], s: [0, 5, 3], h: [0, 3, 1], rocks: 19, mirrors: 12, spares: [1, 2, 0], carriers: [2, 2]),
        row(4.0, r: [0, 5, 6], s: [0, 4, 4], h: [0, 3, 1], rocks: 20, mirrors: 13, spares: [1, 3, 0], carriers: [3, 2]),
        row(4.0, r: [0, 5, 7], s: [0, 4, 4], h: [0, 3, 2], rocks: 20, mirrors: 13, spares: [1, 3, 0], carriers: [3, 2]),
        row(4.0, r: [0, 4, 8], s: [0, 4, 5], h: [0, 2, 3], rocks: 20, mirrors: 14, spares: [1, 3, 0], carriers: [3, 2]),
        row(4.0, r: [0, 4, 8], s: [0, 3, 6], h: [0, 2, 3], rocks: 21, mirrors: 14, spares: [1, 3, 0], carriers: [3, 2]),
        row(4.0, r: [0, 3, 9], s: [0, 3, 6], h: [0, 2, 4], rocks: 21, mirrors: 15, spares: [1, 3, 0], carriers: [3, 3]),
        row(4.0, r: [0, 3, 10], s: [0, 3, 7], h: [0, 2, 4], rocks: 22, mirrors: 15, spares: [1, 3, 0], carriers: [3, 3]),
        row(3.0, r: [0, 0, 5], s: [0, 0, 0], h: [0, 0, 3], boss: 1, rocks: 8, mirrors: 6, spares: [0, 2, 2], carriers: [0, 3]),
        row(4.0, r: [0, 2, 10], s: [0, 2, 7], h: [0, 1, 5], rocks: 22, mirrors: 15, spares: [1, 3, 0], carriers: [3, 3]),
        row(4.0, r: [0, 2, 11], s: [0, 2, 8], h: [0, 1, 5], rocks: 22, mirrors: 16, spares: [1, 3, 0], carriers: [3, 3]),
        row(4.0, r: [0, 2, 11], s: [0, 2, 8], h: [0, 0, 6], rocks: 23, mirrors: 16, spares: [1, 4, 0], carriers: [3, 3]),
        row(4.5, r: [0, 1, 12], s: [0, 1, 9], h: [0, 0, 6], rocks: 23, mirrors: 17, spares: [1, 4, 0], carriers: [3, 3]),
        row(4.5, r: [0, 1, 12], s: [0, 1, 9], h: [0, 0, 7], rocks: 24, mirrors: 17, spares: [1, 4, 0], carriers: [3, 3]),
        row(4.5, r: [0, 0, 13], s: [0, 0, 10], h: [0, 0, 7], rocks: 24, mirrors: 18, spares: [0, 4, 0], carriers: [3, 3]),
        row(4.5, r: [0, 0, 14], s: [0, 0, 10], h: [0, 0, 8], rocks: 25, mirrors: 18, spares: [0, 4, 0], carriers: [3, 3]),
        row(5.0, r: [0, 0, 15], s: [0, 0, 11], h: [0, 0, 8], rocks: 25, mirrors: 19, spares: [0, 5, 0], carriers: [3, 3]),
        row(5.0, r: [0, 0, 16], s: [0, 0, 12], h: [0, 0, 9], rocks: 26, mirrors: 19, spares: [0, 5, 0], carriers: [3, 3]),
        row(3.0, r: [0, 0, 6], s: [0, 0, 2], h: [0, 0, 4], boss: 1, rocks: 10, mirrors: 8, spares: [0, 3, 2], carriers: [0, 3]),
    ]

    /// Levels are 1-based; 0 is the hunter test; out-of-range clamps.
    static func forLevel(_ level: Int) -> LevelConfig {
        if level == 0 { return hunterTest }
        return all[max(1, min(level, count)) - 1]
    }
}
