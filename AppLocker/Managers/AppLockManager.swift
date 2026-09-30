import Foundation
import AppKit
import LocalAuthentication
import Combine
import SwiftUI
import ServiceManagement


// MARK: - AppLock Manager
class AppLockManager: ObservableObject {
    static let shared = AppLockManager()
    
    @Published var protectedApps: [ProtectedApp] = []
    @Published var isMonitoring: Bool = false
    @Published var launchAtLogin: Bool = false {
        didSet {
            toggleLaunchAtLogin(enabled: launchAtLogin)
        }
    }
    
    private var runningAppsObserver: NSObjectProtocol?
    private var terminatedAppsObserver: NSObjectProtocol?
    private var blockedPIDs: Set<pid_t> = []
    private var unlockedBundleIDs: Set<String> = []
    private var passwordPromptShowing: Bool = false
    private let appsKey = "ProtectedApps"
    
    private init() {
        loadApps()
        checkLaunchAtLoginStatus()
        startMonitoring()
    }
    
    // MARK: - Persistence
    func loadApps() {
        if let data = UserDefaults.standard.data(forKey: appsKey),
           let decoded = try? JSONDecoder().decode([ProtectedApp].self, from: data) {
            protectedApps = decoded
        }
    }
    
    func saveApps() {
        if let encoded = try? JSONEncoder().encode(protectedApps) {
            UserDefaults.standard.set(encoded, forKey: appsKey)
        }
    }
    
    // MARK: - Add / Remove Apps
    func addApp(_ app: ProtectedApp) {
        guard !protectedApps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) else { return }
        protectedApps.append(app)
        saveApps()
    }
    
    func removeApp(id: UUID) {
        protectedApps.removeAll { $0.id == id }
        saveApps()
    }
    
    func toggleApp(id: UUID) {
        if let index = protectedApps.firstIndex(where: { $0.id == id }) {
            protectedApps[index].isEnabled.toggle()
            saveApps()
        }
    }
    
    // MARK: - Launch at Login
    private func checkLaunchAtLoginStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
    
    private func toggleLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled { return }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to toggle launch at login: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Monitoring
    func startMonitoring() {
        guard runningAppsObserver == nil else { return }
        isMonitoring = true
        runningAppsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            self.handleAppLaunch(bundleID: bundleID, pid: app.processIdentifier, runningApp: app)
        }
        
        terminatedAppsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            self.unlockedBundleIDs.remove(bundleID)
        }
    }
    
    func stopMonitoring() {
        if let observer = runningAppsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            runningAppsObserver = nil
        }
        if let observer = terminatedAppsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            terminatedAppsObserver = nil
        }
        isMonitoring = false
    }
    
    private func handleAppLaunch(bundleID: String, pid: pid_t, runningApp: NSRunningApplication) {
        guard let protectedApp = protectedApps.first(where: {
            $0.bundleIdentifier == bundleID && $0.isEnabled
        }) else { return }
        
        guard !blockedPIDs.contains(pid) else { return }
        guard !unlockedBundleIDs.contains(bundleID) else { return }
        guard !passwordPromptShowing else { return }
        
        blockedPIDs.insert(pid)
        passwordPromptShowing = true
        
        // Immediately terminate the app
        runningApp.terminate()
        
        // Show Touch ID / Password prompt
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.showAuthenticationPrompt(for: protectedApp, bundleID: bundleID, pid: pid)
        }
    }
    
    private func showAuthenticationPrompt(for app: ProtectedApp, bundleID: String, pid: pid_t) {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        
        let reason = "Unlock \(app.name)"
        var error: NSError?
        
        // Check if authentication is possible
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evalError in
                DispatchQueue.main.async {
                    self.passwordPromptShowing = false
                    self.blockedPIDs.remove(pid)
                    
                    if success {
                        // ✅ Authenticated — Relaunch the app
                        self.unlockedBundleIDs.insert(bundleID)
                        NSWorkspace.shared.launchApplication(
                            withBundleIdentifier: bundleID,
                            options: [],
                            additionalEventParamDescriptor: nil,
                            launchIdentifier: nil
                        )
                    } else {
                        // ❌ Failed or Cancelled - app stays closed
                        print("Authentication failed or cancelled.")
                    }
                }
            }
        } else {
            // Fallback if no auth available (very rare on mac)
            self.passwordPromptShowing = false
            self.blockedPIDs.remove(pid)
        }
    }
}
