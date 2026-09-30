import Foundation

// MARK: - Protected App Model
struct ProtectedApp: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var bundleIdentifier: String
    var isEnabled: Bool
    
    init(id: UUID = UUID(), name: String, bundleIdentifier: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.isEnabled = isEnabled
    }
}
