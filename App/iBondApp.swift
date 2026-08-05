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
}

struct GameView: View {
    @State private var scene: GameScene = {
        let scene = GameScene()
        scene.scaleMode = .resizeFill
        return scene
    }()
    @State private var phase: GamePhase = .menu

    var body: some View {
        ZStack {
            SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()

            // Full-screen overlay for menu/finished; also blocks game touches.
            if phase != .playing {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                VStack(spacing: 28) {
                    Text(phase == .menu ? "iBond" : "Done!")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Button(phase == .menu ? "Start!" : "Back") {
                        if phase == .menu {
                            scene.startGame()
                            phase = .playing
                        } else {
                            phase = .menu
                        }
                    }
                    .font(.title2.bold())
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.2, green: 0.65, blue: 0.9))
                }
            }
        }
        .statusBarHidden()
        .onAppear {
            scene.onAllNPCsEliminated = { phase = .finished }
        }
    }
}
