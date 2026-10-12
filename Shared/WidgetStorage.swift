import Foundation

// App Groups require a valid Apple signing/provisioning setup for the app AND its widget extension.
enum WidgetStorage {
    static let group = "group.com.uniflow.widgets"
    private static let snapshotKey = "workspaceSnapshot.v1"
    private static let pageKey = "timelinePage.v1"
    static var defaults: UserDefaults? { UserDefaults(suiteName: group) }
    static func read() -> UniFlowWorkspace? {
        guard let raw = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(UniFlowWorkspace.self, from: raw)
    }
    static func save(_ data: UniFlowWorkspace) throws {
        guard let defaults else { throw NSError(domain: "UniFlowWidget", code: 100,
            userInfo: [NSLocalizedDescriptionKey: "App Group fehlt. Signiere App und Widget mit derselben App-Group-Berechtigung."]) }
        defaults.set(try JSONEncoder().encode(data), forKey: snapshotKey)
        defaults.set(0, forKey: pageKey)
    }
    static func reset() {
        defaults?.removeObject(forKey: snapshotKey)
        defaults?.removeObject(forKey: pageKey)
    }
    static var page: Int {
        get { max(0, min(20, defaults?.integer(forKey: pageKey) ?? 0)) }
        set { defaults?.set(max(0, min(20, newValue)), forKey: pageKey) }
    }
}
