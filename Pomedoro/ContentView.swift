import SwiftUI
import AVFoundation
import CoreAudio

// Add these color extensions after the existing imports
extension Color {
    static let workColor = Color(red: 0.91, green: 0.3, blue: 0.24)
    static let breakColor = Color(red: 0.2, green: 0.67, blue: 0.52)
}

// MARK: - Pomodoro Timer Model

class PomodoroTimer: ObservableObject {
    // User-configurable durations (in seconds)
    @Published var workDuration: Int = 25 * 60 {
        didSet {
            if isWorkSession && !isRunning {
                timeRemaining = workDuration
            }
        }
    }
    
    @Published var breakDuration: Int = 5 * 60 {
        didSet {
            if !isWorkSession && !isRunning {
                timeRemaining = breakDuration
            }
        }
    }
    
    @Published var longBreakDuration: Int = 15 * 60
    @Published var intervalsUntilLongBreak: Int = 4
    @Published var completedIntervals: Int = 0
    
    // Initialize with a default timeRemaining equal to workDuration.
    @Published var timeRemaining: Int = 25 * 60
    @Published var isRunning = false
    @Published var isWorkSession = true
    
    private var timer: Timer?
    
    // Add this new property to track if timer was running before screen lock
    private var wasRunningBeforeLock = false
    
    private let audioManager = PomodoroAudioManager()
    
    @Published var soundVolume: Float = 0.75 {
        didSet {
            audioManager.soundVolume = soundVolume
        }
    }
    
    init() {
    }
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            } else {
                self.toggleSession()
            }
        }
    }
    
    func pause() {
        isRunning = false
        timer?.invalidate()
    }
    
    func reset() {
        pause()
        isWorkSession = true
        completedIntervals = 0
        timeRemaining = workDuration
    }
    
    private func toggleSession() {
        if isWorkSession {
            // Switching from work to break
            completedIntervals += 1
            isWorkSession = false
            
            // Determine if it's time for a long break
            if completedIntervals >= intervalsUntilLongBreak {
                timeRemaining = longBreakDuration
                completedIntervals = 0 // Reset counter
            } else {
                timeRemaining = breakDuration
            }
        } else {
            // Switching from break to work
            isWorkSession = true
            timeRemaining = workDuration
        }
        
        // Remove scheduleNotification call
        playSound(named: isWorkSession ? "work" : "break")
    }
    
    private func playSound(named: String) {
        audioManager.playSound(named: named)
    }
    
    func cleanup() {
        pause()
        timer?.invalidate()
        timer = nil
        audioManager.cleanup()
    }
    
    func handleScreenLock() {
        if isRunning {
            wasRunningBeforeLock = true
            pause()
        }
    }
    
    // Optional: Add auto-resume when screen unlocks
    func handleScreenUnlock() {
        if wasRunningBeforeLock {
            start()
            wasRunningBeforeLock = false
        }
    }
    
    deinit {
        cleanup()
    }
}

// MARK: - Timer View

struct TimerView: View {
    @ObservedObject var pomodoroTimer: PomodoroTimer
    @State private var isTransitioning = false
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 16)
            
            // Timer display with animation
            Text(timeString(from: pomodoroTimer.timeRemaining))
                .font(.system(size: 64, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
                .scaleEffect(isTransitioning ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isTransitioning)
                .fixedSize(horizontal: true, vertical: true)
            
            // Session type indicator with animated background
            Text(pomodoroTimer.isWorkSession ? "Work Session" : "Break Time")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(pomodoroTimer.isWorkSession ? Color.workColor : Color.breakColor)
                        .animation(.easeInOut(duration: 0.5), value: pomodoroTimer.isWorkSession)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                )
            
            // Interval counter with fade transition
            Text("\(pomodoroTimer.completedIntervals) / \(pomodoroTimer.intervalsUntilLongBreak) until long break")
                .font(.caption)
                .foregroundColor(.secondary)
                .opacity(isTransitioning ? 0.5 : 1.0)
                .animation(.easeInOut, value: isTransitioning)
            
            // Control buttons.
            HStack(spacing: 16) {
                Button(action: toggleTimer) {
                    Text(pomodoroTimer.isRunning ? "Pause" : "Start")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button(action: pomodoroTimer.reset) {
                    Text("Reset")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            
            Spacer(minLength: 16)
        }
        .padding()
    }
    
    private func triggerTransitionAnimation() {
        isTransitioning = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isTransitioning = false
        }
    }
    
    // Helper: Format seconds into MM:SS.
    private func timeString(from seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
    
    private func toggleTimer() {
        if pomodoroTimer.isRunning {
            pomodoroTimer.pause()
        } else {
            pomodoroTimer.start()
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var pomodoroTimer: PomodoroTimer
    
    var body: some View {
        Form {
            Section(header: Text("Work Session Duration (minutes)")) {
                Stepper(value: Binding(
                    get: { pomodoroTimer.workDuration / 60 },
                    set: { pomodoroTimer.workDuration = $0 * 60 }
                ), in: 1...120) {
                    Text("\(pomodoroTimer.workDuration / 60) minutes")
                }
            }
            
            Section(header: Text("Break Durations")) {
                Stepper(value: Binding(
                    get: { pomodoroTimer.breakDuration / 60 },
                    set: { pomodoroTimer.breakDuration = $0 * 60 }
                ), in: 1...60) {
                    Text("Short Break: \(pomodoroTimer.breakDuration / 60) minutes")
                }
                
                Stepper(value: Binding(
                    get: { pomodoroTimer.longBreakDuration / 60 },
                    set: { pomodoroTimer.longBreakDuration = $0 * 60 }
                ), in: 15...45) {
                    Text("Long Break: \(pomodoroTimer.longBreakDuration / 60) minutes")
                }
            }
            
            Section(header: Text("Long Break Interval")) {
                Stepper(value: Binding(
                    get: { pomodoroTimer.intervalsUntilLongBreak },
                    set: { pomodoroTimer.intervalsUntilLongBreak = $0 }
                ), in: 2...8) {
                    Text("Long break after \(pomodoroTimer.intervalsUntilLongBreak) Pomodoros")
                }
            }
            
            Section(header: Text("Sound Settings")) {
                HStack {
                    Image(systemName: "speaker.wave.1")
                    Slider(
                        value: $pomodoroTimer.soundVolume,
                        in: 0...1,
                        step: 0.05
                    ) {
                        Text("Notification Volume")
                    }
                    Image(systemName: "speaker.wave.3")
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .padding([.horizontal, .bottom])
        .frame(maxHeight: .infinity)
    }
}

// MARK: - ContentView (Tab View)

struct ContentView: View {
    @StateObject var pomodoroTimer = PomodoroTimer()
    @State private var selectedView: Int = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Picker("", selection: $selectedView) { // Removed "View" text
                    Text("Timer").tag(0)
                    Text("Settings").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .labelsHidden() // Hide the label completely
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            // Content
            Group {
                if selectedView == 0 {
                    TimerView(pomodoroTimer: pomodoroTimer)
                } else {
                    SettingsView(pomodoroTimer: pomodoroTimer)
                }
            }
            .transition(.opacity)
            .animation(.easeInOut, value: selectedView)
        }
        .frame(minWidth: 300, maxWidth: 400, minHeight: 300)
        .background(Color(NSColor.windowBackgroundColor))
        .onDisappear {
            pomodoroTimer.cleanup()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewLayout(.sizeThatFits)
            .preferredColorScheme(.dark)
    }
}
