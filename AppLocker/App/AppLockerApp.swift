import SwiftUI
import AppKit

@main
struct AppLockerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 700, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

// MARK: - App Delegate
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var fallbackWindow: NSWindow?
    private var didAuthenticateToQuit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Manager is initialized as a singleton — monitoring starts in its init()
        _ = AppLockManager.shared
        NSApp.setActivationPolicy(.regular)
        setupStatusItem()
    }

    // MARK: - Menu Bar
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: "AppLocker")
            button.toolTip = "AppLocker — protection is running"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open AppLocker", action: #selector(showMainWindow), keyEquivalent: ""))
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit AppLocker", action: #selector(quitApp), keyEquivalent: "q")
        menu.addItem(quitItem)

        for menuItem in menu.items where menuItem.action != nil {
            menuItem.target = self
        }

        item.menu = menu
        statusItem = item
    }

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.contentViewController is NSHostingController<ContentView> }) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        if let window = fallbackWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        // SwiftUI released the window — build a new one hosting the same view.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "AppLocker"
        window.contentViewController = NSHostingController(rootView: ContentView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        fallbackWindow = window
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in background even when window is closed
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return false
    }

    // MARK: - Quit Protection
    /// Don't let AppLocker be quit silently while apps are protected —
    /// otherwise the password would never be asked in the background.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if didAuthenticateToQuit { return .terminateNow }

        let manager = AppLockManager.shared
        guard manager.hasActiveProtection else { return .terminateNow }

        manager.authenticate(reason: "Authenticate to quit AppLocker and stop protecting your apps") { [weak self] success in
            guard let self = self else { return }
            if success {
                self.didAuthenticateToQuit = true
                manager.stopMonitoring()
                NSApp.terminate(nil)
            } else {
                print("[AppLocker] Quit cancelled — protection stays active")
            }
        }
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLockManager.shared.stopMonitoring()
    }
}
