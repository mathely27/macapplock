import AppKit
import ApplicationServices
import Combine
import LocalAuthentication
import ServiceManagement
import SwiftUI
import os

@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()

    @Published private(set) var protectedApps: [ProtectedApp] = []
    @Published private(set) var isMonitoring = false
    @Published private(set) var hasAccessibilityPermission = false
    @Published private(set) var launchAtLogin = false
    @Published var statusMessage: String?

    private let appsKey = "ProtectedApps"
    private var observers: [NSObjectProtocol] = []
    private var screenObservers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var session = LockSession()
    private var context: LAContext?
    private var authenticationID: UUID?
    private var pendingApp: NSRunningApplication?
    private var shieldWindows: [NSWindow] = []
    private var windowObservers: [pid_t: AXObserver] = [:]
    private var watchedWindows: [pid_t: [AXUIElement]] = [:]
    private var authorizedWindows: [AXUIElement] = []
    private var activationDeadline: Date?
    private var sessionIsActive = true
    private var authorizedWindowIDs: Set<CGWindowID> = []
    private var lastDiagnostic: String?
    private let logger = Logger(subsystem: "com.applock.AppLocker", category: "Protection")

    private init() {
        if let data = UserDefaults.standard.data(forKey: appsKey),
           let saved = try? JSONDecoder().decode([ProtectedApp].self, from: data) {
            var seen = Set<String>()
            protectedApps = saved.filter {
                $0.bundleIdentifier != Bundle.main.bundleIdentifier && seen.insert($0.bundleIdentifier).inserted
            }
        }
        refreshPermissionsAndLogin()
        startMonitoring()
    }

    private func identity(_ app: NSRunningApplication) -> ProcessIdentity {
        ProcessIdentity(pid: app.processIdentifier, launchedAt: app.launchDate)
    }

    private func isProtected(_ app: NSRunningApplication) -> Bool {
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
        return protectedApps.contains { $0.bundleIdentifier == app.bundleIdentifier && $0.isEnabled }
    }

    func checkAccessibilityPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
    }

    private func saveApps() {
        do { UserDefaults.standard.set(try JSONEncoder().encode(protectedApps), forKey: appsKey) }
        catch { statusMessage = "Could not save your protected apps: \(error.localizedDescription)" }
    }

    func addApp(_ app: ProtectedApp) {
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier,
              !protectedApps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) else { return }
        protectedApps.append(app)
        saveApps()
        scan()
    }

    func removeApp(id: UUID) {
        guard let app = protectedApps.first(where: { $0.id == id }) else { return }
        authenticate(reason: "Remove protection from \(app.name)") { [weak self] success in
            guard let self, success else { return }
            self.protectedApps.removeAll { $0.id == id }
            self.saveApps()
            self.session.revoke()
        }
    }

    func toggleApp(id: UUID) {
        guard let app = protectedApps.first(where: { $0.id == id }) else { return }
        let change: (Bool) -> Void = { [weak self] success in
            guard let self, success,
                  let index = self.protectedApps.firstIndex(where: { $0.id == id }) else { return }
            self.protectedApps[index].isEnabled = !app.isEnabled
            self.saveApps()
            self.session.revoke()
            self.scan()
        }
        if app.isEnabled { authenticate(reason: "Disable protection for \(app.name)", completion: change) }
        else { change(true) }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if !enabled && hasActiveProtection {
            authenticate(reason: "Stop AppLocker from protecting apps automatically at login") { [weak self] success in
                if success { self?.updateLogin(enabled) }
            }
        } else { updateLogin(enabled) }
    }

    private func updateLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { statusMessage = "Could not update Launch at Login: \(error.localizedDescription)" }
        refreshPermissionsAndLogin()
        if enabled && SMAppService.mainApp.status == .requiresApproval {
            statusMessage = "Allow AppLocker in System Settings → General → Login Items."
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private func refreshPermissionsAndLogin() {
        checkAccessibilityPermission()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var hasActiveProtection: Bool { protectedApps.contains { $0.isEnabled } }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                    if name == NSWorkspace.didActivateApplicationNotification,
                       let self, self.session.allows(self.identity(app)) {
                        self.activationDeadline = nil
                    }
                    self?.watchWindows(of: app)
                    if name != NSWorkspace.didLaunchApplicationNotification || app.isActive {
                        self?.intercept(app, explicitOpen: true)
                    }
                }
            })
        }
        for name in [NSWorkspace.didDeactivateApplicationNotification, NSWorkspace.didHideApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self,
                          let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          self.pendingApp == nil else { return }
                    let process = self.identity(app)
                    if self.session.process == process { self.activationDeadline = nil }
                    self.session.revoke(process)
                }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let process = self.identity(app)
                if self.pendingApp.map({ self.identity($0) }) == process { self.cancelPendingAuthentication() }
                self.session.revoke(process)
                self.removeWindowObserver(app.processIdentifier)
            }
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sessionIsActive = false
                    self?.cancelPendingAuthentication()
                    self?.session.revoke()
                }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sessionIsActive = true
                    self?.session.revoke()
                    self?.scan()
                }
            })
        }
        let distributed = DistributedNotificationCenter.default()
        screenObservers.append(distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sessionIsActive = false
                self?.cancelPendingAuthentication()
                self?.session.revoke()
            }
        })
        screenObservers.append(distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sessionIsActive = true
                self?.session.revoke()
                self?.scan()
            }
        })
        timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        scan()
    }

    func stopMonitoring() {
        isMonitoring = false
        cancelPendingAuthentication()
        session.revoke()
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        screenObservers.forEach(DistributedNotificationCenter.default().removeObserver)
        screenObservers.removeAll()
        timer?.invalidate()
        timer = nil
        for pid in Array(windowObservers.keys) { removeWindowObserver(pid) }
    }

    private func scan() {
        guard isMonitoring, sessionIsActive else { return }
        checkAccessibilityPermission()
        let apps = NSWorkspace.shared.runningApplications.filter { isProtected($0) && !$0.isTerminated }
        let pids = Set(apps.map(\.processIdentifier))
        for pid in Array(windowObservers.keys) where !pids.contains(pid) { removeWindowObserver(pid) }
        for app in apps { watchWindows(of: app) }

        if let deadline = activationDeadline {
            if let front = NSWorkspace.shared.frontmostApplication, session.allows(identity(front)), front.isActive {
                activationDeadline = nil
            } else if Date() >= deadline {
                activationDeadline = nil
                session.revoke()
            }
        }
        if let process = session.process, session.isAuthorized, activationDeadline == nil {
            if let app = apps.first(where: { identity($0) == process }) {
                let visible = visibleWindowIDs(of: app)
                let previousWindowsGone = !authorizedWindowIDs.isEmpty && visible.map { authorizedWindowIDs.isDisjoint(with: $0) } == true
                if !app.isActive || app.isHidden || previousWindowsGone ||
                    !WindowVisibility.shouldIntercept(explicitOpen: false,
                        accessibilityWindowCount: usableWindows(of: app)?.count,
                        visibleWindowCount: visible?.count) {
                    session.revoke(process)
                    authorizedWindows = []
                    authorizedWindowIDs = []
                } else if let visible, !visible.isEmpty {
                    authorizedWindowIDs = visible
                }
            } else { session.revoke(process) }
        }
        // Background launches stay locked without stealing focus or killing unsaved work.
        if let front = NSWorkspace.shared.frontmostApplication { intercept(front) }
    }

    private func intercept(_ app: NSRunningApplication, explicitOpen: Bool = false) {
        guard isMonitoring, sessionIsActive, !app.isTerminated, isProtected(app) else { return }
        let process = identity(app)
        guard !session.allows(process) else { return }
        let axCount = usableWindows(of: app)?.count
        let visibleCount = visibleWindowIDs(of: app)?.count
        let shouldIntercept = WindowVisibility.shouldIntercept(explicitOpen: explicitOpen,
            accessibilityWindowCount: axCount, visibleWindowCount: visibleCount)
        let diagnostic = "bundle=\(app.bundleIdentifier ?? "unknown") AX=\(axCount.map(String.init) ?? "unknown") visible=\(visibleCount.map(String.init) ?? "unknown") explicit=\(explicitOpen) intercept=\(shouldIntercept)"
        if diagnostic != lastDiagnostic {
            logger.notice("\(diagnostic, privacy: .public)")
            lastDiagnostic = diagnostic
        }
        guard shouldIntercept else { return }
        // A pending prompt never gives any other app a free pass.
        if pendingApp != nil || authenticationID != nil {
            app.hide()
            return
        }
        guard hasAccessibilityPermission else {
            app.hide()
            NSApp.activate(ignoringOtherApps: true)
            statusMessage = "Enable AppLocker in System Settings → Privacy & Security → Accessibility before unlocking protected apps."
            return
        }
        guard let request = session.begin(process) else { return }
        logger.notice("Presenting lock for \(app.bundleIdentifier ?? "unknown", privacy: .public)")
        pendingApp = app
        activationDeadline = nil
        app.hide()
        NSApp.activate(ignoringOtherApps: true)
        showShield(for: app.localizedName ?? "this app", unlock: { [weak self, weak app] in
            guard let self, let app, self.session.requestID == request else { return }
            self.unlock(app, request: request, process: process)
        }, cancel: { [weak self] in
            self?.cancelPendingAuthentication()
        })
    }

    private func unlock(_ app: NSRunningApplication, request: UUID, process: ProcessIdentity) {
        guard authenticationID == nil else { return }
        logger.notice("Starting authentication for \(app.bundleIdentifier ?? "unknown", privacy: .public)")
        authenticate(reason: "Unlock \(app.localizedName ?? "protected app")") { [weak self, weak app] success in
            guard let self, let app, self.session.requestID == request else { return }
            let accepted = success && self.isMonitoring && self.sessionIsActive && !app.isTerminated && self.isProtected(app)
            self.logger.notice("Authentication completed accepted=\(accepted)")
            if !accepted {
                // Keep a visible lock screen after cancel or failure. No prompt loop.
                app.hide()
                return
            }
            guard self.session.finish(request, process: process, success: true) else { return }
            self.pendingApp = nil
            self.authorizedWindows = self.usableWindows(of: app) ?? []
            self.authorizedWindowIDs = self.visibleWindowIDs(of: app) ?? []
            self.activationDeadline = Date().addingTimeInterval(3)
            self.dismissShield()
            app.unhide()
            // activate() can return false during an asynchronous handoff.
            // Reopen the existing process through Launch Services instead.
            if let url = app.bundleURL {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                configuration.createsNewApplicationInstance = false
                NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] opened, error in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        guard self.session.allows(process) else {
                            opened?.hide()
                            return
                        }
                        if let error {
                            self.session.revoke(process)
                            self.activationDeadline = nil
                            app.hide()
                            self.statusMessage = "Could not open \(app.localizedName ?? "the app"): \(error.localizedDescription)"
                        } else if let opened, self.identity(opened) != process {
                            self.session.revoke(process)
                            self.activationDeadline = nil
                            opened.hide()
                        }
                    }
                }
            } else { _ = app.activate(options: [.activateIgnoringOtherApps]) }
        }
    }

    // A fresh context is created for every request. No grace period and no cached Touch ID.
    func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        guard authenticationID == nil else {
            statusMessage = "Finish the current authentication first."
            completion(false)
            return
        }
        let id = UUID()
        authenticationID = id
        let context = LAContext()
        self.context = context
        context.localizedCancelTitle = "Cancel"
        context.touchIDAuthenticationAllowableReuseDuration = 0
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            self.context = nil
            authenticationID = nil
            statusMessage = error?.localizedDescription ?? "Mac authentication is unavailable. Protection remains locked."
            completion(false)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, _ in
            DispatchQueue.main.async {
                guard let self, self.authenticationID == id else { return }
                self.context = nil
                self.authenticationID = nil
                completion(success)
            }
        }
    }

    private func cancelPendingAuthentication() {
        authenticationID = nil
        context?.invalidate()
        context = nil
        pendingApp?.hide()
        pendingApp = nil
        activationDeadline = nil
        session.revoke()
        dismissShield()
    }

    // MARK: Window lifecycle (Dock reopen can use the same PID without a new activation)
    private func visibleWindowIDs(of app: NSRunningApplication) -> Set<CGWindowID>? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        return Set(windows.compactMap { info -> CGWindowID? in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, pid == app.processIdentifier,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double, width >= 64,
                  let height = bounds["Height"] as? Double, height >= 64,
                  let id = info[kCGWindowNumber as String] as? CGWindowID else { return nil }
            return id
        })
    }

    private func usableWindows(of app: NSRunningApplication) -> [AXUIElement]? {
        guard hasAccessibilityPermission else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.filter { window in
            var minimized: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
            return (minimized as? Bool) != true
        }
    }

    private func watchWindows(of app: NSRunningApplication) {
        guard hasAccessibilityPermission, isProtected(app), !app.isTerminated else { return }
        let pid = app.processIdentifier
        if windowObservers[pid] == nil {
            var observer: AXObserver?
            let result = AXObserverCreate(pid, { _, element, notification, refcon in
                guard let refcon else { return }
                let manager = Unmanaged<AppLockManager>.fromOpaque(refcon).takeUnretainedValue()
                MainActor.assumeIsolated { manager.windowChanged(element, notification: notification as String) }
            }, &observer)
            guard result == .success, let observer else { return }
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.1)
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            for notification in [kAXWindowCreatedNotification, kAXApplicationActivatedNotification] {
                AXObserverAddNotification(observer, element, notification as CFString, pointer)
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            windowObservers[pid] = observer
        }
        guard let observer = windowObservers[pid], let windows = usableWindows(of: app) else { return }
        let old = watchedWindows[pid] ?? []
        for window in old where !windows.contains(where: { CFEqual($0, window) }) {
            for name in [kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification] {
                AXObserverRemoveNotification(observer, window, name as CFString)
            }
        }
        for window in windows where !old.contains(where: { CFEqual($0, window) }) {
            for name in [kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification] {
                AXObserverAddNotification(observer, window, name as CFString, Unmanaged.passUnretained(self).toOpaque())
            }
        }
        watchedWindows[pid] = windows
        if session.allows(identity(app)) { authorizedWindows = windows }
    }

    private func windowChanged(_ element: AXUIElement, notification: String) {
        if notification == kAXUIElementDestroyedNotification || notification == kAXWindowMiniaturizedNotification {
            authorizedWindows.removeAll { CFEqual($0, element) }
            if session.isAuthorized && authorizedWindows.isEmpty {
                session.revoke()
                activationDeadline = nil
            }
        }
        // Preserve destruction before creation order even on an immediate Dock reopen.
        DispatchQueue.main.async { [weak self] in self?.scan() }
    }

    private func removeWindowObserver(_ pid: pid_t) {
        if let observer = windowObservers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        watchedWindows.removeValue(forKey: pid)
    }

    private func showShield(for name: String, unlock: @escaping () -> Void, cancel: @escaping () -> Void) {
        dismissShield()
        for screen in NSScreen.screens {
            let panel = AppLockPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.level = .normal
            panel.backgroundColor = .windowBackgroundColor
            panel.isOpaque = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView:
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 56))
                    Text("\(name) is locked").font(.title)
                    Text("Authenticate before viewing this app.").foregroundColor(.secondary)
                    Button("Unlock with Touch ID or Mac Password", action: unlock)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                    Button("Cancel", action: cancel)
                        .keyboardShortcut(.cancelAction)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            )
            panel.makeKeyAndOrderFront(nil)
            shieldWindows.append(panel)
        }
    }

    private func dismissShield() {
        shieldWindows.forEach { $0.orderOut(nil) }
        shieldWindows.removeAll()
    }
}

@MainActor
private final class AppLockPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
