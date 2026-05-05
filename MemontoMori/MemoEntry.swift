import Foundation

struct MemoEntry: Identifiable, Codable, Equatable {
    var id: String
    var isEnabled: Bool

    init(id: String, isEnabled: Bool = true) {
        self.id = id
        self.isEnabled = isEnabled
    }

    var displayName: String {
        Self.displayName(for: id)
    }

    static func displayName(for id: String) -> String {
        URL(fileURLWithPath: id).deletingPathExtension().lastPathComponent
    }
}
