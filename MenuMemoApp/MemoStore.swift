import Foundation
import AppKit
import SwiftUI
import Combine

final class MemoStore: ObservableObject {
    static let directoryName = "MemontoMori"
    static let supportedExtensions: Set<String> = ["txt", "md"]

    private static let entriesKey = "memontoMori.entries"
    private static let intervalKey = "memontoMori.rotationInterval"
    private static let idleKey = "memontoMori.idleTimeout"
    private static let lastIDKey = "memontoMori.lastDisplayedID"

    @Published private(set) var entries: [MemoEntry] = []

    @Published var rotationInterval: TimeInterval {
        didSet { UserDefaults.standard.set(rotationInterval, forKey: Self.intervalKey) }
    }

    @Published var idleTimeout: TimeInterval {
        didSet { UserDefaults.standard.set(idleTimeout, forKey: Self.idleKey) }
    }

    @Published var lastDisplayedID: String? {
        didSet { UserDefaults.standard.set(lastDisplayedID, forKey: Self.lastIDKey) }
    }

    let directoryURL: URL

    private var pendingWrites: [String: String] = [:]
    private var debounceTask: Task<Void, Never>?

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        self.directoryURL = documents.appendingPathComponent(Self.directoryName, isDirectory: true)

        let defaults = UserDefaults.standard
        let storedInterval = defaults.object(forKey: Self.intervalKey) as? TimeInterval
        let storedIdle = defaults.object(forKey: Self.idleKey) as? TimeInterval
        self.rotationInterval = storedInterval ?? 600
        self.idleTimeout = storedIdle ?? 600
        self.lastDisplayedID = defaults.string(forKey: Self.lastIDKey)

        ensureDirectoryExists()
        rescan()
    }

    func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func rescan() {
        ensureDirectoryExists()

        let stored = loadStoredEntries()

        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
        } catch {
            entries = []
            return
        }

        let presentNames: Set<String> = Set(urls.compactMap { url in
            Self.supportedExtensions.contains(url.pathExtension.lowercased())
                ? url.lastPathComponent
                : nil
        })

        var ordered: [MemoEntry] = stored.compactMap { entry in
            presentNames.contains(entry.id) ? entry : nil
        }
        let knownIDs = Set(ordered.map(\.id))
        let newNames = presentNames.subtracting(knownIDs).sorted()
        for name in newNames {
            ordered.append(MemoEntry(id: name, isEnabled: true))
        }

        entries = ordered
        saveEntries()
    }

    func setEnabled(id: String, enabled: Bool) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].isEnabled = enabled
        saveEntries()
    }

    func move(from source: IndexSet, to destination: Int) {
        entries.move(fromOffsets: source, toOffset: destination)
        saveEntries()
    }

    @discardableResult
    func createMemo(name: String) -> Result<String, Error> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(MemoStoreError.emptyName)
        }
        guard !trimmed.contains("/") else {
            return .failure(MemoStoreError.invalidName)
        }
        let lower = trimmed.lowercased()
        let fileName: String = (lower.hasSuffix(".md") || lower.hasSuffix(".txt"))
            ? trimmed
            : trimmed + ".md"
        let url = directoryURL.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            return .failure(MemoStoreError.alreadyExists)
        }
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
            rescan()
            return .success(fileName)
        } catch {
            return .failure(error)
        }
    }

    func deleteMemo(id: String) {
        flushPending(id: id)
        let url = directoryURL.appendingPathComponent(id)
        var resultingURL: NSURL?
        try? FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        rescan()
    }

    func read(id: String) -> String {
        if let pending = pendingWrites[id] { return pending }
        let url = directoryURL.appendingPathComponent(id)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func scheduleWrite(id: String, content: String) {
        pendingWrites[id] = content
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                self?.flushPending()
            }
        }
    }

    func flushPending() {
        guard !pendingWrites.isEmpty else { return }
        for (id, content) in pendingWrites {
            let url = directoryURL.appendingPathComponent(id)
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
        pendingWrites = [:]
    }

    private func flushPending(id: String) {
        guard let content = pendingWrites.removeValue(forKey: id) else { return }
        let url = directoryURL.appendingPathComponent(id)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    func modificationDate(id: String) -> Date? {
        let url = directoryURL.appendingPathComponent(id)
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }

    func revealInFinder() {
        ensureDirectoryExists()
        NSWorkspace.shared.open(directoryURL)
    }

    var enabledEntries: [MemoEntry] {
        entries.filter { $0.isEnabled }
    }

    private func loadStoredEntries() -> [MemoEntry] {
        guard let data = UserDefaults.standard.data(forKey: Self.entriesKey),
              let decoded = try? JSONDecoder().decode([MemoEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveEntries() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.entriesKey)
        }
    }
}

enum MemoStoreError: LocalizedError {
    case emptyName
    case invalidName
    case alreadyExists

    var errorDescription: String? {
        switch self {
        case .emptyName: return "ファイル名が空です"
        case .invalidName: return "ファイル名に / は使えません"
        case .alreadyExists: return "同名のファイルがすでに存在します"
        }
    }
}
