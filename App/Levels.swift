import CoreGraphics

/// Battery types: fixed stats that never scale with level. Picking one up
/// overwrites both the remaining charge AND the type; every level starts
/// with a full Red. Difficulty comes from the enemy tier mix and the battery
/// economy, not from capacity.
enum BatteryType: Int, CaseIterable {
    case red    // the classic laser
    case orange // double power: kills shielded enemies twice as fast
    case white  // quadruple power; flies straight through rocks, mirrors,
                // and every enemy on the line (no reflection, no self-hit)

    /// Seconds of firing time when full (uniform across types since
    /// 2026-08-09 — the power multiplier alone differentiates them).
    var capacity: Double { [3.0, 3.0, 3.0][rawValue] }
    /// Damage multiplier vs shields (kill time = shield / power).
    var power: Double { [1.0, 2.0, 4.0][rawValue] }
    var piercing: Bool { self == .white }
}

/// Per-tier enemy attributes; index 0..2 = tier I..III. Shields are seconds
/// of red-beam contact (kill time = shield / battery power; 0 = instant).
enum EnemyTiers {
    static let runnerSpeed = [130.0, 170.0, 210.0]
    static let runnerShield = [0.0, 0.5, 1.2]
    static let shooterAim = [1.5, 1.1, 0.8]
    static let shooterShield = [0.0, 0.6, 1.4]
    static let hunterApproach = [190.0, 210.0, 230.0]
    static let hunterAim = [0.6, 0.5, 0.4]
    static let hunterShield = [0.0, 1.0, 2.2]
}

/// A boss: a huge (3×) version of a regular kind+tier, with the three armor
/// rings as its health bar. Behavior follows its kind — huge runners chase,
/// huge shooters ambush, huge hunters patrol. All bosses kill on touch.
struct BossSpec {
    enum Kind { case runner, shooter, hunter }
    let kind: Kind
    let tier: Int
    /// Seconds of red beam to kill (rings peel per third).
    let shield: Double
}

/// Shared boss body stats plus per-kind derivations from the tier tables:
/// huge runners chase at ~55% of their tier's speed, huge shooters aim ~40%
/// slower, huge hunters approach at ~50%.
enum BossStats {
    static let radius = 42.0
    static let mass = 9.0
    static let patrolSpeed = 35.0
    static func runnerSpeed(tier: Int) -> Double { EnemyTiers.runnerSpeed[tier] * 0.55 }
    static func shooterAim(tier: Int) -> Double { EnemyTiers.shooterAim[tier] * 1.4 }
    static func hunterApproach(tier: Int) -> Double { EnemyTiers.hunterApproach[tier] * 0.5 }
    static func hunterAim(tier: Int) -> Double { [0.8, 0.65, 0.5][tier] }
}

/// One level's composition. The 100-row table is generated from the decade
/// rules in docs/superpowers/specs/2026-08-09-tiers-batteries-bosses-plan.md
/// (one new kind per decade, huge boss of that kind every 10th level);
/// individual rows are hand-tunable.
struct LevelConfig {
    /// The map spans this many screens in each dimension.
    let mapScale: CGFloat
    /// Per-tier counts, index 0..2 = tier I..III.
    let runners: [Int]
    let shooters: [Int]
    let hunters: [Int]
    let bosses: [BossSpec]
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

    static let count = 100

    /// Compact row builder: r/s/h are per-tier counts, spares is
    /// [red, orange, white], carriers is [shooter→red, hunter→orange].
    private static func row(_ map: Double, r: [Int], s: [Int], h: [Int],
                            rocks: Int, mirrors: Int,
                            spares: [Int], carriers: [Int],
                            bosses: [BossSpec] = []) -> LevelConfig {
        LevelConfig(mapScale: CGFloat(map), runners: r, shooters: s, hunters: h,
                    bosses: bosses, rockCount: rocks, mirrorCount: mirrors,
                    redSpares: spares[0], orangeSpares: spares[1],
                    whiteSpares: spares[2],
                    shooterRedCarriers: carriers[0],
                    hunterOrangeCarriers: carriers[1])
    }

    /// Dev-only hunter proving ground ("level 0" in the dev grid).
    static let hunterTest = row(2.0, r: [0, 0, 0], s: [0, 0, 0], h: [3, 0, 0],
                                rocks: 8, mirrors: 6, spares: [1, 1, 0],
                                carriers: [0, 1])

    static let all: [LevelConfig] = [
        row(1.0, r: [2, 0, 0], s: [0, 0, 0], h: [0, 0, 0], rocks: 0, mirrors: 0, spares: [0, 0, 0], carriers: [0, 0]), // 1
        row(1.0, r: [3, 0, 0], s: [0, 0, 0], h: [0, 0, 0], rocks: 0, mirrors: 0, spares: [0, 0, 0], carriers: [0, 0]),
        row(1.0, r: [4, 0, 0], s: [0, 0, 0], h: [0, 0, 0], rocks: 3, mirrors: 0, spares: [0, 0, 0], carriers: [0, 0]),
        row(1.0, r: [5, 0, 0], s: [0, 0, 0], h: [0, 0, 0], rocks: 3, mirrors: 0, spares: [0, 0, 0], carriers: [0, 0]),
        row(1.0, r: [6, 0, 0], s: [0, 0, 0], h: [0, 0, 0], rocks: 3, mirrors: 0, spares: [0, 0, 0], carriers: [0, 0]),
        row(1.5, r: [7, 0, 0], s: [0, 0, 0], h: [0, 0, 0], rocks: 3, mirrors: 1, spares: [0, 0, 0], carriers: [0, 0]),
        row(1.5, r: [8, 0, 0], s: [0, 0, 0], h: [0, 0, 0], rocks: 4, mirrors: 1, spares: [0, 0, 0], carriers: [0, 0]),
        row(1.5, r: [9, 0, 0], s: [0, 0, 0], h: [0, 0, 0], rocks: 4, mirrors: 1, spares: [0, 0, 0], carriers: [0, 0]),
        row(1.5, r: [10, 0, 0], s: [0, 0, 0], h: [0, 0, 0], rocks: 4, mirrors: 1, spares: [0, 0, 0], carriers: [0, 0]),
        row(2.0, r: [4, 0, 0], s: [0, 0, 0], h: [0, 0, 0], rocks: 6, mirrors: 3, spares: [6, 0, 0], carriers: [0, 0], bosses: [BossSpec(kind: .runner, tier: 0, shield: 14)]), // 10
        row(1.5, r: [5, 0, 0], s: [1, 0, 0], h: [0, 0, 0], rocks: 5, mirrors: 2, spares: [1, 0, 0], carriers: [0, 0]), // 11
        row(1.5, r: [5, 0, 0], s: [1, 0, 0], h: [0, 0, 0], rocks: 5, mirrors: 2, spares: [1, 0, 0], carriers: [1, 0]),
        row(1.5, r: [5, 0, 0], s: [2, 0, 0], h: [0, 0, 0], rocks: 5, mirrors: 2, spares: [1, 0, 0], carriers: [1, 0]),
        row(1.5, r: [6, 0, 0], s: [2, 0, 0], h: [0, 0, 0], rocks: 5, mirrors: 2, spares: [1, 0, 0], carriers: [1, 0]),
        row(1.5, r: [6, 0, 0], s: [3, 0, 0], h: [0, 0, 0], rocks: 6, mirrors: 2, spares: [2, 0, 0], carriers: [2, 0]),
        row(2.0, r: [6, 0, 0], s: [3, 0, 0], h: [0, 0, 0], rocks: 6, mirrors: 3, spares: [2, 0, 0], carriers: [2, 0]),
        row(2.0, r: [7, 0, 0], s: [4, 0, 0], h: [0, 0, 0], rocks: 6, mirrors: 3, spares: [2, 0, 0], carriers: [2, 0]),
        row(2.0, r: [7, 0, 0], s: [4, 0, 0], h: [0, 0, 0], rocks: 6, mirrors: 3, spares: [2, 0, 0], carriers: [2, 0]),
        row(2.0, r: [7, 0, 0], s: [5, 0, 0], h: [0, 0, 0], rocks: 7, mirrors: 3, spares: [2, 0, 0], carriers: [2, 0]),
        row(2.0, r: [5, 0, 0], s: [0, 0, 0], h: [0, 0, 0], rocks: 6, mirrors: 4, spares: [1, 3, 0], carriers: [0, 0], bosses: [BossSpec(kind: .shooter, tier: 0, shield: 16)]), // 20
        row(2.0, r: [5, 0, 0], s: [3, 0, 0], h: [1, 0, 0], rocks: 7, mirrors: 4, spares: [2, 1, 0], carriers: [2, 0]), // 21
        row(2.0, r: [5, 0, 0], s: [3, 0, 0], h: [1, 0, 0], rocks: 7, mirrors: 4, spares: [2, 1, 0], carriers: [2, 0]),
        row(2.0, r: [5, 0, 0], s: [3, 0, 0], h: [1, 0, 0], rocks: 8, mirrors: 4, spares: [2, 1, 0], carriers: [2, 1]),
        row(2.0, r: [5, 0, 0], s: [3, 0, 0], h: [2, 0, 0], rocks: 8, mirrors: 4, spares: [2, 1, 0], carriers: [2, 1]),
        row(2.0, r: [5, 0, 0], s: [3, 0, 0], h: [2, 0, 0], rocks: 8, mirrors: 4, spares: [2, 1, 0], carriers: [2, 1]),
        row(2.5, r: [5, 0, 0], s: [3, 0, 0], h: [2, 0, 0], rocks: 8, mirrors: 5, spares: [2, 1, 0], carriers: [2, 1]),
        row(2.5, r: [5, 0, 0], s: [3, 0, 0], h: [3, 0, 0], rocks: 9, mirrors: 5, spares: [2, 1, 0], carriers: [2, 1]),
        row(2.5, r: [5, 0, 0], s: [3, 0, 0], h: [3, 0, 0], rocks: 9, mirrors: 5, spares: [2, 1, 0], carriers: [2, 1]),
        row(2.5, r: [5, 0, 0], s: [3, 0, 0], h: [3, 0, 0], rocks: 9, mirrors: 5, spares: [2, 1, 0], carriers: [2, 1]),
        row(2.5, r: [4, 0, 0], s: [2, 0, 0], h: [1, 0, 0], rocks: 7, mirrors: 5, spares: [0, 3, 1], carriers: [0, 1], bosses: [BossSpec(kind: .hunter, tier: 0, shield: 18)]), // 30
        row(2.5, r: [4, 1, 0], s: [3, 0, 0], h: [2, 0, 0], rocks: 10, mirrors: 6, spares: [1, 2, 0], carriers: [2, 1]), // 31
        row(2.5, r: [4, 1, 0], s: [3, 0, 0], h: [2, 0, 0], rocks: 10, mirrors: 6, spares: [1, 2, 0], carriers: [2, 1]),
        row(2.5, r: [4, 2, 0], s: [3, 0, 0], h: [2, 0, 0], rocks: 10, mirrors: 6, spares: [1, 2, 0], carriers: [2, 1]),
        row(2.5, r: [4, 2, 0], s: [3, 0, 0], h: [2, 0, 0], rocks: 10, mirrors: 6, spares: [1, 2, 0], carriers: [2, 1]),
        row(2.5, r: [4, 3, 0], s: [3, 0, 0], h: [2, 0, 0], rocks: 11, mirrors: 6, spares: [1, 2, 0], carriers: [2, 1]),
        row(2.5, r: [4, 3, 0], s: [3, 0, 0], h: [2, 0, 0], rocks: 11, mirrors: 7, spares: [1, 2, 0], carriers: [2, 1]),
        row(2.5, r: [4, 4, 0], s: [3, 0, 0], h: [2, 0, 0], rocks: 11, mirrors: 7, spares: [1, 2, 0], carriers: [2, 1]),
        row(2.5, r: [4, 4, 0], s: [3, 0, 0], h: [2, 0, 0], rocks: 11, mirrors: 7, spares: [1, 2, 0], carriers: [2, 1]),
        row(2.5, r: [4, 5, 0], s: [3, 0, 0], h: [2, 0, 0], rocks: 12, mirrors: 7, spares: [1, 2, 0], carriers: [2, 1]),
        row(2.5, r: [0, 3, 0], s: [2, 0, 0], h: [1, 0, 0], rocks: 7, mirrors: 5, spares: [0, 3, 1], carriers: [0, 1], bosses: [BossSpec(kind: .runner, tier: 1, shield: 20)]), // 40
        row(3.0, r: [4, 4, 0], s: [2, 1, 0], h: [2, 0, 0], rocks: 12, mirrors: 8, spares: [1, 2, 0], carriers: [2, 2]), // 41
        row(3.0, r: [4, 4, 0], s: [2, 1, 0], h: [2, 0, 0], rocks: 12, mirrors: 8, spares: [1, 2, 0], carriers: [2, 2]),
        row(3.0, r: [4, 4, 0], s: [2, 2, 0], h: [2, 0, 0], rocks: 13, mirrors: 8, spares: [1, 2, 0], carriers: [2, 2]),
        row(3.0, r: [4, 4, 0], s: [2, 2, 0], h: [2, 0, 0], rocks: 13, mirrors: 8, spares: [1, 2, 0], carriers: [2, 2]),
        row(3.0, r: [4, 4, 0], s: [2, 3, 0], h: [2, 0, 0], rocks: 13, mirrors: 8, spares: [1, 2, 0], carriers: [2, 2]),
        row(3.0, r: [4, 4, 0], s: [2, 3, 0], h: [2, 0, 0], rocks: 13, mirrors: 9, spares: [1, 2, 0], carriers: [2, 2]),
        row(3.0, r: [4, 4, 0], s: [2, 4, 0], h: [2, 0, 0], rocks: 14, mirrors: 9, spares: [1, 2, 0], carriers: [2, 2]),
        row(3.0, r: [4, 4, 0], s: [2, 4, 0], h: [2, 0, 0], rocks: 14, mirrors: 9, spares: [1, 2, 0], carriers: [2, 2]),
        row(3.0, r: [4, 4, 0], s: [2, 5, 0], h: [2, 0, 0], rocks: 14, mirrors: 9, spares: [1, 2, 0], carriers: [2, 2]),
        row(2.5, r: [2, 3, 0], s: [0, 2, 0], h: [1, 0, 0], rocks: 8, mirrors: 6, spares: [0, 3, 1], carriers: [0, 1], bosses: [BossSpec(kind: .shooter, tier: 1, shield: 22)]), // 50
        row(3.0, r: [3, 4, 0], s: [2, 3, 0], h: [2, 1, 0], rocks: 15, mirrors: 10, spares: [1, 3, 0], carriers: [3, 2]), // 51
        row(3.0, r: [3, 4, 0], s: [2, 3, 0], h: [2, 1, 0], rocks: 15, mirrors: 10, spares: [1, 3, 0], carriers: [3, 2]),
        row(3.0, r: [3, 4, 0], s: [2, 3, 0], h: [2, 1, 0], rocks: 15, mirrors: 10, spares: [1, 3, 0], carriers: [3, 2]),
        row(3.0, r: [3, 4, 0], s: [2, 3, 0], h: [2, 2, 0], rocks: 15, mirrors: 10, spares: [1, 3, 0], carriers: [3, 2]),
        row(3.0, r: [3, 4, 0], s: [2, 3, 0], h: [2, 2, 0], rocks: 16, mirrors: 10, spares: [1, 3, 0], carriers: [3, 2]),
        row(3.5, r: [3, 4, 0], s: [2, 3, 0], h: [2, 2, 0], rocks: 16, mirrors: 11, spares: [1, 3, 0], carriers: [3, 2]),
        row(3.5, r: [3, 4, 0], s: [2, 3, 0], h: [2, 3, 0], rocks: 16, mirrors: 11, spares: [1, 3, 0], carriers: [3, 2]),
        row(3.5, r: [3, 4, 0], s: [2, 3, 0], h: [2, 3, 0], rocks: 16, mirrors: 11, spares: [1, 3, 0], carriers: [3, 2]),
        row(3.5, r: [3, 4, 0], s: [2, 3, 0], h: [2, 3, 0], rocks: 17, mirrors: 11, spares: [1, 3, 0], carriers: [3, 2]),
        row(3.0, r: [0, 4, 0], s: [0, 2, 0], h: [1, 1, 0], rocks: 8, mirrors: 6, spares: [0, 3, 2], carriers: [0, 2], bosses: [BossSpec(kind: .hunter, tier: 1, shield: 24)]), // 60
        row(3.5, r: [3, 3, 1], s: [2, 3, 0], h: [1, 2, 0], rocks: 17, mirrors: 12, spares: [0, 3, 0], carriers: [3, 2]), // 61
        row(3.5, r: [3, 3, 1], s: [2, 3, 0], h: [1, 2, 0], rocks: 17, mirrors: 12, spares: [0, 3, 0], carriers: [3, 2]),
        row(3.5, r: [3, 3, 2], s: [2, 3, 0], h: [1, 2, 0], rocks: 18, mirrors: 12, spares: [0, 3, 0], carriers: [3, 2]),
        row(3.5, r: [3, 3, 2], s: [2, 3, 0], h: [1, 2, 0], rocks: 18, mirrors: 12, spares: [0, 3, 0], carriers: [3, 2]),
        row(3.5, r: [3, 3, 3], s: [2, 3, 0], h: [1, 2, 0], rocks: 18, mirrors: 12, spares: [0, 3, 0], carriers: [3, 2]),
        row(3.5, r: [3, 3, 3], s: [2, 3, 0], h: [1, 2, 0], rocks: 18, mirrors: 13, spares: [0, 3, 0], carriers: [3, 2]),
        row(3.5, r: [3, 3, 4], s: [2, 3, 0], h: [1, 2, 0], rocks: 19, mirrors: 13, spares: [0, 3, 0], carriers: [3, 2]),
        row(3.5, r: [3, 3, 4], s: [2, 3, 0], h: [1, 2, 0], rocks: 19, mirrors: 13, spares: [0, 3, 0], carriers: [3, 2]),
        row(3.5, r: [3, 3, 5], s: [2, 3, 0], h: [1, 2, 0], rocks: 19, mirrors: 13, spares: [0, 3, 0], carriers: [3, 2]),
        row(3.0, r: [0, 3, 2], s: [0, 2, 0], h: [0, 2, 0], rocks: 9, mirrors: 7, spares: [0, 3, 2], carriers: [0, 2], bosses: [BossSpec(kind: .runner, tier: 2, shield: 26)]), // 70
        row(4.0, r: [2, 3, 4], s: [1, 2, 1], h: [1, 2, 0], rocks: 20, mirrors: 14, spares: [0, 4, 0], carriers: [3, 3]), // 71
        row(4.0, r: [2, 3, 4], s: [1, 2, 1], h: [1, 2, 0], rocks: 20, mirrors: 14, spares: [0, 4, 0], carriers: [3, 3]),
        row(4.0, r: [2, 3, 4], s: [1, 2, 2], h: [1, 2, 0], rocks: 20, mirrors: 14, spares: [0, 4, 0], carriers: [3, 3]),
        row(4.0, r: [2, 3, 4], s: [1, 2, 2], h: [1, 2, 0], rocks: 20, mirrors: 14, spares: [0, 4, 0], carriers: [3, 3]),
        row(4.0, r: [2, 3, 4], s: [1, 2, 3], h: [1, 2, 0], rocks: 21, mirrors: 14, spares: [0, 4, 0], carriers: [3, 3]),
        row(4.0, r: [2, 3, 4], s: [1, 2, 3], h: [1, 2, 0], rocks: 21, mirrors: 15, spares: [0, 4, 0], carriers: [3, 3]),
        row(4.0, r: [2, 3, 4], s: [1, 2, 4], h: [1, 2, 0], rocks: 21, mirrors: 15, spares: [0, 4, 0], carriers: [3, 3]),
        row(4.0, r: [2, 3, 4], s: [1, 2, 4], h: [1, 2, 0], rocks: 21, mirrors: 15, spares: [0, 4, 0], carriers: [3, 3]),
        row(4.0, r: [2, 3, 4], s: [1, 2, 5], h: [1, 2, 0], rocks: 22, mirrors: 15, spares: [0, 4, 0], carriers: [3, 3]),
        row(3.0, r: [0, 2, 3], s: [0, 0, 2], h: [0, 2, 0], rocks: 9, mirrors: 7, spares: [0, 4, 2], carriers: [0, 2], bosses: [BossSpec(kind: .shooter, tier: 2, shield: 28)]), // 80
        row(4.5, r: [2, 2, 4], s: [1, 2, 3], h: [1, 1, 1], rocks: 22, mirrors: 16, spares: [0, 4, 0], carriers: [3, 3]), // 81
        row(4.5, r: [2, 2, 4], s: [1, 2, 3], h: [1, 1, 1], rocks: 22, mirrors: 16, spares: [0, 4, 0], carriers: [3, 3]),
        row(4.5, r: [2, 2, 4], s: [1, 2, 3], h: [1, 1, 1], rocks: 23, mirrors: 16, spares: [0, 4, 0], carriers: [3, 3]),
        row(4.5, r: [2, 2, 4], s: [1, 2, 3], h: [1, 1, 2], rocks: 23, mirrors: 16, spares: [0, 4, 0], carriers: [3, 3]),
        row(4.5, r: [2, 2, 4], s: [1, 2, 3], h: [1, 1, 2], rocks: 23, mirrors: 16, spares: [0, 4, 0], carriers: [3, 3]),
        row(4.5, r: [2, 2, 4], s: [1, 2, 3], h: [1, 1, 2], rocks: 23, mirrors: 17, spares: [0, 4, 0], carriers: [3, 3]),
        row(4.5, r: [2, 2, 4], s: [1, 2, 3], h: [1, 1, 3], rocks: 24, mirrors: 17, spares: [0, 4, 0], carriers: [3, 3]),
        row(4.5, r: [2, 2, 4], s: [1, 2, 3], h: [1, 1, 3], rocks: 24, mirrors: 17, spares: [0, 4, 0], carriers: [3, 3]),
        row(4.5, r: [2, 2, 4], s: [1, 2, 3], h: [1, 1, 3], rocks: 24, mirrors: 17, spares: [0, 4, 0], carriers: [3, 3]),
        row(3.0, r: [0, 0, 4], s: [0, 0, 2], h: [0, 1, 1], rocks: 10, mirrors: 8, spares: [0, 4, 3], carriers: [0, 2], bosses: [BossSpec(kind: .hunter, tier: 2, shield: 30)]), // 90
        row(5.0, r: [2, 2, 4], s: [1, 2, 3], h: [1, 1, 2], rocks: 25, mirrors: 18, spares: [0, 5, 0], carriers: [3, 3]), // 91
        row(5.0, r: [2, 2, 4], s: [1, 2, 3], h: [1, 1, 2], rocks: 25, mirrors: 18, spares: [0, 5, 0], carriers: [3, 3]),
        row(5.0, r: [2, 2, 5], s: [1, 2, 3], h: [1, 1, 2], rocks: 25, mirrors: 18, spares: [0, 5, 0], carriers: [3, 3]),
        row(5.0, r: [2, 2, 5], s: [1, 2, 4], h: [1, 1, 3], rocks: 25, mirrors: 18, spares: [0, 5, 0], carriers: [3, 3]),
        row(5.0, r: [2, 2, 5], s: [1, 2, 4], h: [1, 1, 3], rocks: 26, mirrors: 18, spares: [0, 5, 0], carriers: [3, 3]),
        row(5.0, r: [2, 2, 6], s: [1, 2, 4], h: [1, 1, 3], rocks: 26, mirrors: 19, spares: [0, 5, 0], carriers: [3, 3]),
        row(5.0, r: [2, 2, 6], s: [1, 2, 4], h: [1, 1, 3], rocks: 26, mirrors: 19, spares: [0, 5, 0], carriers: [3, 3]),
        row(5.0, r: [2, 2, 6], s: [1, 2, 5], h: [1, 1, 4], rocks: 26, mirrors: 19, spares: [0, 5, 0], carriers: [3, 3]),
        row(5.0, r: [2, 2, 7], s: [1, 2, 5], h: [1, 1, 4], rocks: 26, mirrors: 19, spares: [0, 5, 0], carriers: [3, 3]),
        row(3.5, r: [0, 0, 4], s: [0, 0, 2], h: [0, 0, 2], rocks: 10, mirrors: 8, spares: [0, 5, 4], carriers: [0, 3], bosses: [BossSpec(kind: .runner, tier: 2, shield: 18), BossSpec(kind: .shooter, tier: 2, shield: 18), BossSpec(kind: .hunter, tier: 2, shield: 18)]), // 100
    ]

    /// Levels are 1-based; 0 is the hunter test; out-of-range clamps.
    static func forLevel(_ level: Int) -> LevelConfig {
        if level == 0 { return hunterTest }
        return all[max(1, min(level, count)) - 1]
    }
}
