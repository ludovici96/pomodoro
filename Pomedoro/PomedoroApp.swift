import SwiftUI
import Cocoa

@main
struct PomedoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // An empty scene since the UI is entirely in the status bar popover.
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    // Store observer tokens along with their notification center for proper removal.
    private var observerTokens: [(center: AnyObject, token: NSObjectProtocol)] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar controller
        statusBarController = StatusBarController()
        
        // Prevent app from appearing in dock
        NSApp.setActivationPolicy(.accessory)
        
        // Setup multiple observers for different lock scenarios
        let workspace = NSWorkspace.shared
        let notificationCenter = workspace.notificationCenter
        let distributedCenter = DistributedNotificationCenter.default()
        
        // Screen lock notifications
        let lockNotifications: [(AnyObject, String)] = [
            (notificationCenter, NSWorkspace.sessionDidResignActiveNotification.rawValue),
            (notificationCenter, NSWorkspace.screensDidSleepNotification.rawValue),
            (distributedCenter, "com.apple.screenIsLocked"),
            (distributedCenter, "com.apple.loginwindow.lock")
        ]
        
        // Screen unlock notifications
        let unlockNotifications: [(AnyObject, String)] = [
            (notificationCenter, NSWorkspace.sessionDidBecomeActiveNotification.rawValue),
            (notificationCenter, NSWorkspace.screensDidWakeNotification.rawValue),
            (distributedCenter, "com.apple.screenIsUnlocked"),
            (distributedCenter, "com.apple.loginwindow.unlock")
        ]
        
        // Add lock observers
        for (center, name) in lockNotifications {
            let observer = (center as? NotificationCenter ?? distributedCenter).addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.statusBarController?.handleScreenLock()
            }
            observerTokens.append((center: center, token: observer))
        }
        
        // Add unlock observers
        for (center, name) in unlockNotifications {
            let observer = (center as? NotificationCenter ?? distributedCenter).addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.statusBarController?.handleScreenUnlock()
            }
            observerTokens.append((center: center, token: observer))
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean up all observers using the stored pairs.
        for (center, token) in observerTokens {
            if let center = center as? NotificationCenter {
                center.removeObserver(token)
            } else if let center = center as? DistributedNotificationCenter {
                center.removeObserver(token)
            }
        }
        observerTokens.removeAll()
        
        statusBarController?.cleanup()
    }
}

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: EventMonitor?
    private var contentView: ContentView!
    private var menu: NSMenu!

    override init() {
        super.init()
        
        // Initialize ContentView first
        contentView = ContentView()
        
        // Create the status bar item first
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        // Create the menu but don't assign it to statusItem yet
        menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        // Configure status bar button
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Pomodoro Timer")
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Create the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 300)
        popover.behavior = .applicationDefined
        popover.animates = true
        
        // Create a hosting controller that allows flexible sizing
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController
        
        // Configure event monitor for outside clicks
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.popover.isShown else { return }
            self.hidePopover(sender: event)
        }
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent {
            if event.type == .rightMouseUp {
                statusItem.menu = menu // Set menu only for right click
                statusItem.button?.performClick(nil) // Show the menu
                statusItem.menu = nil // Remove menu after click
            } else {
                togglePopover(sender)
            }
        }
    }
    
    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            hidePopover(sender: sender)
        } else {
            showPopover(sender: sender)
        }
    }
    
    private func showPopover(sender: Any?) {
        guard let statusBarButton = statusItem.button else { return }
        
        popover.show(relativeTo: statusBarButton.bounds, of: statusBarButton, preferredEdge: .minY)
        eventMonitor?.start()
        
        // Ensure app is active
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func hidePopover(sender: Any?) {
        popover.performClose(sender)
        eventMonitor?.stop()
    }
    
    func cleanup() {
        hidePopover(sender: nil)
        NSStatusBar.system.removeStatusItem(statusItem)
    }
    
    func handleScreenLock() {
        if let hostingController = popover.contentViewController as? NSHostingController<ContentView> {
            let contentView = hostingController.rootView
            contentView.pomodoroTimer.handleScreenLock()
        }
    }
    
    func handleScreenUnlock() {
        if let hostingController = popover.contentViewController as? NSHostingController<ContentView> {
            let contentView = hostingController.rootView
            contentView.pomodoroTimer.handleScreenUnlock()
        }
    }
    
    deinit {
        cleanup()
    }
}

// Add this class to handle click events outside the popover
class EventMonitor {
    private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent?) -> Void
    
    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }
    
    deinit {
        stop()
    }
    
    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }
    
    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
