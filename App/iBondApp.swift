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
    /// Config menu (controls picker), toggled by the gear icon.
    @State private var showConfigMenu = false
    /// Selected control scheme; applied when the next game starts.
    @AppStorage("controlScheme") private var controlSchemeRaw = ControlScheme.joystick.rawValue

    /// True on the finished overlay after beating the last level.
    private var wonTheGame: Bool {
        phase == .finished && level >= LevelConfig.count
    }

    private var overlayTitle: String {
        switch phase {
        case .menu: return "Laser Taser"
        case .playing: return ""
        case .finished:
            if wonTheGame { return "You won!" }
            return level == 0 ? "Test done!" : "Level \(level) done!"
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
                        start(level: level)
                    }
                    .font(.title2.bold())
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.2, green: 0.65, blue: 0.9))

                    if showConfigMenu {
                        controlsPicker
                    }
                    if showDevMenu {
                        devLevelGrid
                    }
                }

                // Corner icons: gear toggles the config menu, wrench the
                // developer level picker.
                VStack {
                    HStack {
                        Button {
                            showConfigMenu.toggle()
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.35))
                                .padding(16)
                        }
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

    /// Applies the selected control scheme and starts the given level.
    private func start(level: Int) {
        scene.controlScheme = ControlScheme(rawValue: controlSchemeRaw) ?? .joystick
        scene.startGame(level: level)
        phase = .playing
    }

    /// Control scheme picker; the choice persists and applies on next start.
    private var controlsPicker: some View {
        VStack(spacing: 10) {
            Text("CONTROLS")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.5))
            ForEach([(ControlScheme.joystick, "Joystick + Button"),
                     (ControlScheme.tap, "Tap to Move & Fire"),
                     (ControlScheme.stickAndTap, "Stick + Tap Fire")], id: \.0) { scheme, label in
                Button(label) {
                    controlSchemeRaw = scheme.rawValue
                }
                .font(.headline)
                .frame(width: 220, height: 44)
                .background(controlSchemeRaw == scheme.rawValue
                            ? Color(red: 0.2, green: 0.65, blue: 0.9)
                            : Color.white.opacity(0.12))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.top, 8)
    }

    /// Rows of five level buttons; picking one jumps straight into that level.
    private var devLevelGrid: some View {
        VStack(spacing: 10) {
            Text("DEV · pick level")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.5))
            ForEach(Array(stride(from: 1, through: LevelConfig.count, by: 5)),
                    id: \.self) { rowStart in
                HStack(spacing: 10) {
                    ForEach(rowStart..<min(rowStart + 5, LevelConfig.count + 1),
                            id: \.self) { pick in
                        Button("\(pick)") {
                            showDevMenu = false
                            level = pick
                            start(level: pick)
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
            Button("Hunter test") {
                showDevMenu = false
                level = 0
                start(level: 0)
            }
            .font(.headline)
            .frame(width: 152, height: 44)
            .background(level == 0 ? Color(red: 0.2, green: 0.65, blue: 0.9)
                                   : Color.white.opacity(0.12))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.top, 8)
    }
}
