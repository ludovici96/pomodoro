import SwiftUI
import AVFoundation
import CoreAudio
import UserNotifications

extension Color {
    static let workColor = Color(red: 0.91, green: 0.3, blue: 0.24)
    static let breakColor = Color(red: 0.2, green: 0.67, blue: 0.52)
}

class PomodoroTimer: ObservableObject {
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
    @Published var timeRemaining: Int = 25 * 60
    @Published var isRunning = false
    @Published var isWorkSession = true
    
    private var timer: Timer?
    
    private var wasRunningBeforeLock = false
    
    private let audioManager = PomodoroAudioManager()
    
    @Published var soundVolume: Float = 0.75 {
        didSet {
            audioManager.soundVolume = soundVolume
        }
    }
    
    init() { }
    
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
        timer = nil
    }
    
    func reset() {
        pause()
        isWorkSession = true
        completedIntervals = 0
        timeRemaining = workDuration
    }
    
    private func toggleSession() {
        if isWorkSession {
            completedIntervals += 1
            isWorkSession = false

            if completedIntervals >= intervalsUntilLongBreak {
                timeRemaining = longBreakDuration
                completedIntervals = 0
            } else {
                timeRemaining = breakDuration
            }
            sendNotification(title: "Break Time!", body: "Time for a \(timeRemaining / 60) minute break.")
        } else {

            isWorkSession = true
            timeRemaining = workDuration
            sendNotification(title: "Time to Focus!", body: "Let's start a \(timeRemaining / 60) minute work session.")
        }
        
        playSound(named: isWorkSession ? "work" : "break")
    }
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error sending notification: \(error.localizedDescription)")
            }
        }
    }
    
    private func playSound(named: String) {
        audioManager.playSound(named: named)
    }
    
    func cleanup() {
        pause()
        audioManager.cleanup()
    }
    
    func handleScreenLock() {
        if isRunning {
            wasRunningBeforeLock = true
            pause()
        }
    }
    
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


struct TimerView: View {
    @ObservedObject var pomodoroTimer: PomodoroTimer
    @State private var isTransitioning = false
    
    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 8)
            Text(timeString(from: pomodoroTimer.timeRemaining))
                .font(.system(size: 48, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
                .scaleEffect(isTransitioning ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isTransitioning)
                .fixedSize(horizontal: true, vertical: true)

            Text(pomodoroTimer.isWorkSession ? "Work Session" : "Break Time")
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(pomodoroTimer.isWorkSession ? Color.workColor : Color.breakColor)
                        .animation(.easeInOut(duration: 0.5), value: pomodoroTimer.isWorkSession)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                )
            
            Text("\(pomodoroTimer.completedIntervals) / \(pomodoroTimer.intervalsUntilLongBreak) until long break")
                .font(.caption)
                .foregroundColor(.secondary)
                .opacity(isTransitioning ? 0.5 : 1.0)
                .animation(.easeInOut, value: isTransitioning)
            
            HStack(spacing: 12) {
                Button(action: toggleTimer) {
                    Text(pomodoroTimer.isRunning ? "Pause" : "Start")
                        .frame(minWidth: 70)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Button(action: pomodoroTimer.reset) {
                    Text("Reset")
                        .frame(minWidth: 70)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            
            Spacer(minLength: 8)
        }
        .padding(12)
    }
    
    private func triggerTransitionAnimation() {
        isTransitioning = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isTransitioning = false
        }
    }

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

struct SettingTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(value)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsView: View {
    @ObservedObject var pomodoroTimer: PomodoroTimer
    @State private var editingTile: String?
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                SettingTile(
                    title: "Work Duration",
                    value: "\(pomodoroTimer.workDuration / 60)m",
                    icon: "timer",
                    color: .workColor
                ) {
                    editingTile = "work"
                }
                
                SettingTile(
                    title: "Break",
                    value: "\(pomodoroTimer.breakDuration / 60)m",
                    icon: "cup.and.saucer",
                    color: .breakColor
                ) {
                    editingTile = "break"
                }
                
                SettingTile(
                    title: "Long Break",
                    value: "\(pomodoroTimer.longBreakDuration / 60)m",
                    icon: "beach.umbrella",
                    color: .blue
                ) {
                    editingTile = "longBreak"
                }
                
                SettingTile(
                    title: "Intervals",
                    value: "\(pomodoroTimer.intervalsUntilLongBreak)",
                    icon: "repeat",
                    color: .purple
                ) {
                    editingTile = "intervals"
                }
                
                SettingTile(
                    title: "Sound",
                    value: "\(Int(pomodoroTimer.soundVolume * 100))%",
                    icon: "speaker.wave.2",
                    color: .orange
                ) {
                    editingTile = "sound"
                }
            }
            .padding(12)
        }
        .sheet(item: $editingTile) { tile in
            SettingDetailView(
                pomodoroTimer: pomodoroTimer,
                settingType: tile,
                isPresented: Binding(
                    get: { editingTile != nil },
                    set: { if !$0 { editingTile = nil } }
                )
            )
            .frame(width: 240, height: 140)
        }
    }
}

struct SettingDetailView: View {
    @ObservedObject var pomodoroTimer: PomodoroTimer
    let settingType: String
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) var colorScheme
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(.body, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            Group {
                switch settingType {
                case "sound":
                    VolumeControl(volume: $pomodoroTimer.soundVolume)
                case "work":
                    EnhancedDurationControl(
                        value: Binding(
                            get: { pomodoroTimer.workDuration / 60 },
                            set: { pomodoroTimer.workDuration = $0 * 60 }
                        ),
                        range: 1...120,
                        icon: "timer",
                        color: .workColor
                    )
                case "break":
                    EnhancedDurationControl(
                        value: Binding(
                            get: { pomodoroTimer.breakDuration / 60 },
                            set: { pomodoroTimer.breakDuration = $0 * 60 }
                        ),
                        range: 1...60,
                        icon: "cup.and.saucer",
                        color: .breakColor
                    )
                case "longBreak":
                    EnhancedDurationControl(
                        value: Binding(
                            get: { pomodoroTimer.longBreakDuration / 60 },
                            set: { pomodoroTimer.longBreakDuration = $0 * 60 }
                        ),
                        range: 15...45,
                        icon: "beach.umbrella",
                        color: .blue
                    )
                case "intervals":
                    EnhancedDurationControl(
                        value: $pomodoroTimer.intervalsUntilLongBreak,
                        range: 2...8,
                        icon: "repeat",
                        color: .purple
                    )
                default:
                    EmptyView()
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .overlay(
            Button("") { isPresented = false }
                .keyboardShortcut(.return, modifiers: [])
                .opacity(0)
        )
        .focused($isFocused)
        .onAppear { isFocused = true }
        .submitScope()
        .onSubmit {
            isPresented = false
        }
    }
    
    private var title: String {
        switch settingType {
        case "work": return "Work Duration"
        case "break": return "Break Duration"
        case "longBreak": return "Long Break Duration"
        case "intervals": return "Intervals Until Long Break"
        case "sound": return "Sound Volume"
        default: return ""
        }
    }
}

struct EnhancedDurationControl: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let icon: String
    let color: Color
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            Text("\(value)")
                .font(.system(size: 32, weight: .medium, design: .rounded))
                .foregroundColor(color)
            HStack(spacing: 16) {
                Button(action: decrement) {
                    Image(systemName: "minus.circle.fill")
                        .imageScale(.large)
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .buttonStyle(.plain)
                .disabled(value <= range.lowerBound)
                
                Image(systemName: icon)
                    .imageScale(.large)
                    .foregroundColor(color)
                
                Button(action: increment) {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.large)
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .buttonStyle(.plain)
                .disabled(value >= range.upperBound)
            }
            .font(.title3)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .focused($isFocused)
        .onAppear { isFocused = true }
    }
    
    private func increment() {
        if value < range.upperBound {
            value += 1
        }
    }
    
    private func decrement() {
        if value > range.lowerBound {
            value -= 1
        }
    }
}

struct VolumeControl: View {
    @Binding var volume: Float
    @FocusState private var isFocused: Bool
    
    private let step: Float = 0.05
    
    var body: some View {
        VStack(spacing: 12) {
            Text("\(volumePercentage)%")
                .font(.system(size: 32, weight: .medium, design: .rounded))
                .foregroundColor(.orange)
            

            HStack {
                Image(systemName: "speaker.wave.1")
                    .foregroundColor(.secondary)
                Slider(value: $volume, in: 0...1, step: step)
                    .tint(.orange)
                Image(systemName: "speaker.wave.3")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .focused($isFocused)
        .onAppear { isFocused = true }
        .overlay(
            HStack {
                Button(action: decreaseVolume) { }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .opacity(0)
                Button(action: increaseVolume) { }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .opacity(0)
            }
        )
    }
    
    private var volumePercentage: Int {
        return Int(round(volume * 20) * 5)
    }
    
    private func increaseVolume() {
        let newValue = round((volume + step) * 20) / 20
        volume = min(1.0, newValue)
    }
    
    private func decreaseVolume() {
        let newValue = round((volume - step) * 20) / 20
        volume = max(0.0, newValue)
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}


struct ContentView: View {
    @StateObject var pomodoroTimer = PomodoroTimer()
    @State private var selectedView: Int = 0
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $selectedView) {
                    Text("Timer").tag(0)
                    Text("Settings").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .controlSize(.small)
                .labelsHidden()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
            
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
        .frame(minWidth: 260, maxWidth: 320, minHeight: 240)
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
