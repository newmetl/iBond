import AVFoundation

/// All game audio. Three looped layers (player laser, shooter aim hum, runner
/// footsteps) are toggled every frame from the scene's current state; kills
/// and shooter shots are one-shots; the music loop starts with the first game
/// and runs forever. The WAVs are synthesized by tools/generate_sounds.py —
/// rerun it (or drop in replacement files) to change the sound set.
final class SoundManager {
    static let shared = SoundManager()

    private let music = makePlayer("music_loop", volume: 0.35, loops: -1)
    private let laser = makePlayer("laser_loop", volume: 0.5, loops: -1)
    private let aim = makePlayer("shooter_aim_loop", volume: 0.45, loops: -1)
    private let steps = makePlayer("runner_steps_loop", volume: 0.4, loops: -1)
    private let zap = makePlayer("shooter_fire", volume: 0.8, loops: 0)
    private let ouch = makePlayer("ouch", volume: 0.8, loops: 0)
    private let playerDeath = makePlayer("player_death", volume: 0.9, loops: 0)

    private static func makePlayer(_ name: String, volume: Float,
                                   loops: Int) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else {
            print("SoundManager: missing or unreadable \(name).wav")
            return nil
        }
        player.volume = volume
        player.numberOfLoops = loops
        player.prepareToPlay()
        return player
    }

    func startMusic() {
        guard music?.isPlaying != true else { return }
        music?.play()
    }

    func setLaserFiring(_ on: Bool) { setLoop(laser, on) }
    func setShooterAiming(_ on: Bool) { setLoop(aim, on) }
    func setRunnersChasing(_ on: Bool) { setLoop(steps, on) }

    func playShooterFire() { replay(zap) }
    /// NPC kills.
    func playOuch() { replay(ouch) }
    /// The player's own death — longer and deeper than the NPC ouch.
    func playPlayerDeath() { replay(playerDeath) }

    /// Loops pause (not stop) so resuming doesn't restart the waveform.
    private func setLoop(_ player: AVAudioPlayer?, _ on: Bool) {
        guard let player else { return }
        if on, !player.isPlaying {
            player.play()
        } else if !on, player.isPlaying {
            player.pause()
        }
    }

    /// One-shots retrigger from the start; a new hit cuts off the last one.
    private func replay(_ player: AVAudioPlayer?) {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }
}
