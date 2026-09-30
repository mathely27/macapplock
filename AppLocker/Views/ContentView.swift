import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var manager = AppLockManager.shared
    @State private var showAddSheet = false
    @State private var searchText = ""

    var filteredApps: [ProtectedApp] {
        if searchText.isEmpty { return manager.protectedApps }
        return manager.protectedApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Protected Applications")) {
                    if manager.protectedApps.isEmpty {
                        HStack {
                            Spacer()
                            Text("No apps protected. Click + to add.")
                                .foregroundColor(.secondary)
                                .padding(.vertical, 20)
                            Spacer()
                        }
                    } else {
                        ForEach(filteredApps) { app in
                            AppRowView(app: app,
                                       onToggle: { manager.toggleApp(id: app.id) },
                                       onRemove: { manager.removeApp(id: app.id) })
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search apps")
            .navigationTitle("AppLocker")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Toggle("Launch at Login", isOn: $manager.launchAtLogin)
                        .toggleStyle(.switch)
                        .help("Start AppLocker automatically when you log in")
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showAddSheet = true }) {
                        Label("Add App", systemImage: "plus")
                    }
                    .help("Add an application to protect")
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddAppView()
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - App Row View
struct AppRowView: View {
    let app: ProtectedApp
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
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { app.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help("Remove protection")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add App View
struct AddAppView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var manager = AppLockManager.shared
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
        if searchText.isEmpty { return installedApps }
        return installedApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Select App to Protect")
                .font(.headline)
                .padding()

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Loading applications...")
                Spacer()
            } else {
                List(filtered) { app in
                    let alreadyAdded = manager.protectedApps.contains(where: {
                        $0.bundleIdentifier == app.bundleIdentifier
                    })
                    
                    HStack {
                        AppIconView(bundleIdentifier: app.bundleIdentifier)
                            .frame(width: 24, height: 24)
                        
                        Text(app.name)
                        
                        Spacer()
                        
                        if alreadyAdded {
                            Text("Added")
                                .foregroundColor(.secondary)
                        } else {
                            Button("Add") {
                                let protected = ProtectedApp(
                                    name: app.name,
                                    bundleIdentifier: app.bundleIdentifier
                                )
                                manager.addApp(protected)
                                dismiss()
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .searchable(text: $searchText, prompt: "Search...")
            }

            Divider()
            
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .padding()
            }
        }
        .frame(width: 450, height: 400)
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
            for dir in dirs {
                let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
                for item in contents where item.hasSuffix(".app") {
                    let fullPath = dir + "/" + item
                    let url = URL(fileURLWithPath: fullPath)
                    if let bundle = Bundle(url: url),
                       let bundleID = bundle.bundleIdentifier {
                        let name = item.replacingOccurrences(of: ".app", with: "")
                        apps.append(InstalledApp(name: name, bundleIdentifier: bundleID, url: url))
                    }
                }
            }
            let sorted = apps.sorted { $0.name < $1.name }
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
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .scaledToFit()
                .foregroundColor(.secondary)
        }
    }
}
