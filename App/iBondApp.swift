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
    /// Developer level picker, toggled by the wrench icon on any overlay.
    @State private var showDevMenu = false

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

                    if showDevMenu {
                        devLevelGrid
                    }
                }

                // Developer corner: wrench toggles the level picker.
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            showDevMenu.toggle()
                        } label: {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.35))
                                .padding(16)
                        }
                    }
                    Spacer()
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

    /// Two rows of level buttons; picking one jumps straight into that level.
    private var devLevelGrid: some View {
        VStack(spacing: 10) {
            Text("DEV · pick level")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.5))
            ForEach([1, 6], id: \.self) { rowStart in
                HStack(spacing: 10) {
                    ForEach(rowStart..<rowStart + 5, id: \.self) { pick in
                        Button("\(pick)") {
                            showDevMenu = false
                            level = pick
                            scene.startGame(level: pick)
                            phase = .playing
                        }
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(pick == level ? Color(red: 0.2, green: 0.65, blue: 0.9)
                                                  : Color.white.opacity(0.12))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding(.top, 8)
    }
}
