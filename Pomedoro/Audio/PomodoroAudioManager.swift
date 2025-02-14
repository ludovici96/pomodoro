import AVFoundation

class PomodoroAudioManager {
    private var audioPlayer: AVAudioPlayer?
    
    var soundVolume: Float = 0.75 {
        didSet {
            audioPlayer?.volume = soundVolume
        }
    }
    
    func playSound(named: String) {
        guard let url = Bundle.main.url(forResource: named, withExtension: "mp3") else {
            print("Could not find sound file: \(named).mp3")
            return
        }
        
        do {
            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.volume = soundVolume
            audioPlayer?.play()
        } catch {
            print("Could not load audio file: \(error.localizedDescription)")
        }
    }
    
    func cleanup() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
}
