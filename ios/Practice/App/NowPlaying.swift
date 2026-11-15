import Combine
import MediaPlayer

/// The lock screen and Control Center: what is playing (the drill's name, or Metronome), with pause, play and stop
/// (Joe, on 0.1.6: "can't figure out how to stop it"). iOS shows an app there, and sends it these commands, only
/// when its sound is not mixed with other apps'; that is the "Lock-screen controls" switch in Settings
/// (AudioEngine.mixesWithOthers), off unless he turns it on, because with it on his music stops when the click starts.
@MainActor
final class NowPlaying {
    private let player: Player
    private let pa: PlayAlong
    private var bag = Set<AnyCancellable>()

    init(player: Player, playAlong: PlayAlong) {
        self.player = player
        self.pa = playAlong
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.pa.phase == .paused { self.play() } else { self.pause() }
            }
            return .success
        }
        c.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stopAll() }
            return .success
        }
        // The values arrive just before they are set, so look again a moment later.
        player.$mode.sink { [weak self] _ in Task { @MainActor in self?.refresh() } }.store(in: &bag)
        playAlong.$phase.sink { [weak self] _ in Task { @MainActor in self?.refresh() } }.store(in: &bag)
    }

    private func play() {
        if pa.phase == .paused { pa.resumeRun() }
    }

    /// A drill is held; the metronome, which has nothing to hold, stops.
    private func pause() {
        if pa.phase == .running { pa.pause() } else if player.mode == .metronome { player.stop() }
    }

    private func stopAll() {
        pa.leave()
        player.stop()
    }

    private func refresh() {
        let center = MPNowPlayingInfoCenter.default()
        let drill = pa.phase == .running || pa.phase == .paused || player.mode == .playAlong
        guard drill || player.mode != .idle else {
            center.nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [MPMediaItemPropertyArtist: "Practice"]
        info[MPMediaItemPropertyTitle] = drill ? pa.exercise.name : "Metronome"
        info[MPNowPlayingInfoPropertyPlaybackRate] = pa.phase == .paused ? 0.0 : 1.0
        center.nowPlayingInfo = info
    }
}
