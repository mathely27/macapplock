import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var manager = AppLockManager.shared
    @State private var showAddSheet = false
    @State private var searchText = ""
    @State private var hoveredAppId: UUID?

    var filteredApps: [ProtectedApp] {
        if searchText.isEmpty { return manager.protectedApps }
        return manager.protectedApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Accessibility Permission Banner
                if !manager.hasAccessibilityPermission {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accessibility Permission Required")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Enable Accessibility to detect window close and reopen reliably.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("Grant Access") {
                            manager.requestAccessibilityPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.orange.opacity(0.3)),
                        alignment: .bottom
                    )
                }

                // Status bar
                HStack {
                    Circle()
                        .fill(manager.isMonitoring ? (manager.hasAccessibilityPermission ? Color.green : Color.orange) : Color.red)
                        .frame(width: 8, height: 8)
                    Text(manager.isMonitoring ? (manager.hasAccessibilityPermission ? "Monitoring Active" : "Setup Required — Accessibility") : "Monitoring Stopped")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(manager.protectedApps.filter(\.isEnabled).count) app\(manager.protectedApps.filter(\.isEnabled).count == 1 ? "" : "s") protected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)

                Divider()

                Text("Protection stays on when AppLocker is closed. Apps lock again when you leave or close them.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)

                // App list
                List {
                    if manager.protectedApps.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("No Protected Apps")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Click the + button to add apps you want to protect with Touch ID or password.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(filteredApps) { app in
                            AppRowView(
                                app: app,
                                isHovered: hoveredAppId == app.id,
                                onToggle: { manager.toggleApp(id: app.id) },
                                onRemove: { manager.removeApp(id: app.id) }
                            )
                            .onHover { isHovered in
                                hoveredAppId = isHovered ? app.id : nil
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let app = filteredApps[index]
                                manager.removeApp(id: app.id)
                            }
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search apps...")
            }
            .navigationTitle("AppLocker")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Label("Background Protection", systemImage: "lock.shield.fill")
                        .help("Closing AppLocker keeps protection running. The installed background service starts at login and restarts after an unexpected exit.")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showAddSheet = true }) {
                        Label("Add App", systemImage: "plus")
                    }
                    .help("Add an application to protect")
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddAppView(manager: manager)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .alert("AppLocker", isPresented: Binding(
            get: { manager.statusMessage != nil },
            set: { if !$0 { manager.statusMessage = nil } }
        )) {
            Button("OK") { manager.statusMessage = nil }
        } message: {
            Text(manager.statusMessage ?? "")
        }
    }
}

// MARK: - App Row View
struct AppRowView: View {
    let app: ProtectedApp
    let isHovered: Bool
    let onToggle: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(bundleIdentifier: app.bundleIdentifier)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.headline)
                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(app.isEnabled ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
                Text(app.isEnabled ? "Protected" : "Disabled")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Toggle("", isOn: Binding(
                get: { app.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .help(app.isEnabled ? "Disable protection" : "Enable protection")

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(isHovered ? 1.0 : 0.6))
            }
            .buttonStyle(.borderless)
            .help("Remove protection")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Add App View
struct AddAppView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var manager: AppLockManager
    @State private var installedApps: [InstalledApp] = []
    @State private var searchText = ""
    @State private var isLoading = true

    struct InstalledApp: Identifiable {
        let id = UUID()
        let name: String
        let bundleIdentifier: String
        let url: URL
    }

    var filtered: [InstalledApp] {
        let nonProtected = installedApps.filter { installed in
            !manager.protectedApps.contains(where: { $0.bundleIdentifier == installed.bundleIdentifier })
        }
        if searchText.isEmpty { return nonProtected }
        return nonProtected.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var alreadyProtected: [InstalledApp] {
        installedApps.filter { installed in
            manager.protectedApps.contains(where: { $0.bundleIdentifier == installed.bundleIdentifier })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add App to Protect")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Scanning applications...")
                    .padding()
                Spacer()
            } else {
                List {
                    if !filtered.isEmpty {
                        Section("Available") {
                            ForEach(filtered) { app in
                                HStack {
                                    AppIconView(bundleIdentifier: app.bundleIdentifier)
                                        .frame(width: 24, height: 24)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(app.name)
                                            .font(.body)
                                        Text(app.bundleIdentifier)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Button("Protect") {
                                        let protected = ProtectedApp(
                                            name: app.name,
                                            bundleIdentifier: app.bundleIdentifier
                                        )
                                        manager.addApp(protected)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    if !alreadyProtected.isEmpty {
                        Section("Already Protected") {
                            ForEach(alreadyProtected) { app in
                                HStack {
                                    AppIconView(bundleIdentifier: app.bundleIdentifier)
                                        .frame(width: 24, height: 24)

                                    Text(app.name)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search applications...")
            }

            Divider()

            HStack {
                Text("\(filtered.count) available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .padding()
            }
            .padding(.leading)
        }
        .frame(width: 500, height: 450)
        .onAppear { loadInstalledApps() }
    }

    private func loadInstalledApps() {
        DispatchQueue.global(qos: .userInitiated).async {
            let dirs = [
                "/Applications",
                "/System/Applications",
                "/System/Applications/Utilities",
                NSHomeDirectory() + "/Applications"
            ]
            var apps: [InstalledApp] = []
            let ownBundleID = Bundle.main.bundleIdentifier ?? ""

            for dir in dirs {
                let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
                for item in contents where item.hasSuffix(".app") {
                    let fullPath = dir + "/" + item
                    let url = URL(fileURLWithPath: fullPath)
                    if let bundle = Bundle(url: url),
                       let bundleID = bundle.bundleIdentifier,
                       bundleID != ownBundleID {
                        let name = item.replacingOccurrences(of: ".app", with: "")
                        apps.append(InstalledApp(name: name, bundleIdentifier: bundleID, url: url))
                    }
                }
            }
            let unique = Dictionary(apps.map { ($0.bundleIdentifier, $0) }, uniquingKeysWith: { first, _ in first }).values
            let sorted = unique.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async {
                self.installedApps = sorted
                self.isLoading = false
            }
        }
    }
}

// MARK: - App Icon View
struct AppIconView: View {
    let bundleIdentifier: String

    var icon: NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }

    var body: some View {
        if let img = icon {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .scaledToFit()
                .foregroundColor(.secondary)
        }
    }
}
