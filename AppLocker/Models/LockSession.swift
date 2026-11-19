import Foundation

/// An unlock belongs to one foreground visit, never to a bundle ID or a time grace period.
struct ProcessIdentity: Hashable {
    let pid: Int32
    let launchedAt: Date?
}

struct LockSession {
    private(set) var process: ProcessIdentity?
    private(set) var requestID: UUID?
    private(set) var isAuthorized = false

    mutating func begin(_ process: ProcessIdentity) -> UUID? {
        guard requestID == nil, !allows(process) else { return nil }
        self.process = process
        let id = UUID()
        requestID = id
        isAuthorized = false
        return id
    }

    @discardableResult
    mutating func finish(_ id: UUID, process: ProcessIdentity, success: Bool) -> Bool {
        guard requestID == id, self.process == process else { return false }
        requestID = nil
        isAuthorized = success
        if !success { self.process = nil }
        return true
    }

    func allows(_ process: ProcessIdentity) -> Bool {
        self.process == process && isAuthorized
    }

    mutating func revoke(_ process: ProcessIdentity? = nil) {
        guard process == nil || self.process == process else { return }
        self.process = nil
        requestID = nil
        isAuthorized = false
    }
}
