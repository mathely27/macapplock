import AppKit
import Carbon
import SwiftUI
import os

// Own the dashboard explicitly: a background launch must not create a SwiftUI window.
@main
@MainActor
struct AppLockerApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let logger = Logger(subsystem: "com.applock.AppLocker", category: "Lifecycle")
    private var statusItem: NSStatusItem?
    private var dashboard: NSWindow?
    private var didAuthenticateToStop = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = AppLockManager.shared
        setupMenu()
        logger.notice("Guard started background=\(CommandLine.arguments.contains("--background"))")
        if !CommandLine.arguments.contains("--background") { showMainWindow() }
    }

    private func setupMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: "AppLocker")
        item.button?.toolTip = "AppLocker — background protection is running"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open AppLocker", action: #selector(showMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Close AppLocker — Keep Protecting", action: #selector(closeDashboard), keyEquivalent: "q"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Stop Protection Until Login…", action: #selector(stopProtection), keyEquivalent: ""))
        for entry in menu.items where entry.action != nil { entry.target = self }
        item.menu = menu
        statusItem = item

        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Close AppLocker — Keep Protecting", action: #selector(closeDashboard), keyEquivalent: "q"))
        appMenu.items.first?.target = self
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)
        // Native text editing shortcuts in the dashboard's search field.
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc func showMainWindow() {
        if dashboard == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 552),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = "AppLocker"
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: ContentView())
            window.center()
            dashboard = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        dashboard?.makeKeyAndOrderFront(nil)
        logger.notice("Dashboard opened")
    }

    @objc func closeDashboard() {
        dashboard?.orderOut(nil)
        restoreBackgroundModeIfNeeded()
        logger.notice("Dashboard closed visible=\(self.dashboard?.isVisible ?? false) monitoring=\(AppLockManager.shared.isMonitoring)")
        // Do not hide NSApp: its password/lock panels must still be able to appear.
    }

    func restoreBackgroundModeIfNeeded() {
        // The lock needs a foreground-capable app even with its dashboard closed.
        if dashboard?.isVisible != true && !AppLockManager.shared.isPresentingLock {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeDashboard()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if didAuthenticateToStop { return .terminateNow }
        let reason = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue
        if let reason, [kAEShutDown, kAERestart, kAEReallyLogOut, kAELogOut].contains(reason) {
            return .terminateNow
        }
        // Dock Quit, Cmd+Q, and closing the dashboard never turn off protection.
        closeDashboard()
        return .terminateCancel
    }

    @objc private func stopProtection() {
        AppLockManager.shared.authenticate(reason: "Stop protecting your apps until the next login") { [weak self] success in
            guard let self, success else { return }
            // Removing a loaded launchd job stops its KeepAlive policy too. Its plist
            // remains installed so protection returns at the next login.
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["bootout", "gui/\(getuid())/com.applock.AppLocker.guard"]
            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus != 0 {
                    AppLockManager.shared.statusMessage = "Could not stop the background service. Protection is still running."
                    self.showMainWindow()
                    return
                }
                self.didAuthenticateToStop = true
                NSApp.terminate(nil)
            } catch {
                AppLockManager.shared.statusMessage = error.localizedDescription
                self.showMainWindow()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLockManager.shared.stopMonitoring()
    }
}
