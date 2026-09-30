import SwiftUI

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
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start monitoring as soon as the app loads
        AppLockManager.shared.startMonitoring()
        NSApp.setActivationPolicy(.regular)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in background even when window is closed
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        AppLockManager.shared.stopMonitoring()
    }
}
