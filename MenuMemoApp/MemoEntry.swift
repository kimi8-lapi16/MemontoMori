import Foundation

struct MemoEntry: Identifiable, Codable, Equatable {
    var id: String
    var isEnabled: Bool

    init(id: String, isEnabled: Bool = true) {
        self.id = id
        self.isEnabled = isEnabled
    }

    var displayName: String {
        (id as NSString).deletingPathExtension
    }
}
