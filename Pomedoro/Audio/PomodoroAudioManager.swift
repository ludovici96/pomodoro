import AVFoundation

class PomodoroAudioManager {
    // Audio engine and nodes
    private let audioEngine = AVAudioEngine()
    private let audioPlayerNode = AVAudioPlayerNode()
    private let gainNode = AVAudioUnitEQ(numberOfBands: 1)
    
    // User-configurable sound volume (0.0 - 1.0)
    var soundVolume: Float = 0.75 {
        didSet {
            audioEngine.mainMixerNode.outputVolume = soundVolume
        }
    }
    
    init() {
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        // Attach the nodes
        audioEngine.attach(audioPlayerNode)
        audioEngine.attach(gainNode)
        
        // Configure the gain node with one band.
        if let band = gainNode.bands.first {
            band.gain = 12.0
            band.filterType = .parametric
            band.bypass = false
        }
        
        // Connect nodes
        audioEngine.connect(audioPlayerNode, to: gainNode, format: nil)
        audioEngine.connect(gainNode, to: audioEngine.mainMixerNode, format: nil)
        
        // Set initial volume
        audioEngine.mainMixerNode.outputVolume = soundVolume
        
        do {
            try audioEngine.start()
        } catch {
            print("AudioEngine failed to start: \(error.localizedDescription)")
        }
    }
    
    func playSound(named: String) {
        guard let url = Bundle.main.url(forResource: named, withExtension: "mp3") else {
            print("Could not find sound file: \(named).mp3")
            return
        }
        
        do {
            let audioFile = try AVAudioFile(forReading: url)
            audioPlayerNode.stop()
            audioPlayerNode.scheduleFile(audioFile, at: nil) {
                // Optional completion handler
            }
            audioPlayerNode.play()
        } catch {
            print("Could not load audio file: \(error.localizedDescription)")
        }
    }
    
    func cleanup() {
        audioPlayerNode.stop()
        audioEngine.stop()
    }
}
