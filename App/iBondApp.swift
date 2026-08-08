import SwiftUI
import SpriteKit

@main
struct IBondApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
        }
    }
}

enum GamePhase {
    case menu
    case playing
    case finished
    case gameOver
}

struct GameView: View {
    @State private var scene: GameScene = {
        let scene = GameScene()
        scene.scaleMode = .resizeFill
        return scene
    }()
    @State private var phase: GamePhase = .menu
    /// The level currently being played (or about to be); survives relaunches.
    @AppStorage("currentLevel") private var level = 1

    /// True on the finished overlay after beating the last level.
    private var wonTheGame: Bool {
        phase == .finished && level >= LevelConfig.count
    }

    private var overlayTitle: String {
        switch phase {
        case .menu: return "Laser Taser"
        case .playing: return ""
        case .finished: return wonTheGame ? "You won!" : "Level \(level) done!"
        case .gameOver: return "Game over!"
        }
    }

    private var buttonTitle: String {
        switch phase {
        case .menu: return "Start!"
        case .playing: return ""
        case .finished: return wonTheGame ? "Play again" : "Continue"
        case .gameOver: return "Restart" // retries the same level
        }
    }

    var body: some View {
        ZStack {
            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()

            // Full-screen overlay for menu/finished; also blocks game touches.
            if phase != .playing {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                VStack(spacing: 28) {
                    Text(overlayTitle)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Button(buttonTitle) {
                        if phase == .finished {
                            level = wonTheGame ? 1 : level + 1
                        }
                        scene.startGame(level: level)
                        phase = .playing
                    }
                    .font(.title2.bold())
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.2, green: 0.65, blue: 0.9))
                }
            }
        }
        .statusBarHidden()
        .onAppear {
            level = min(max(level, 1), LevelConfig.count) // heal a bad stored value
            scene.onAllNPCsEliminated = { phase = .finished }
            scene.onPlayerKilled = { phase = .gameOver }
        }
    }
}
