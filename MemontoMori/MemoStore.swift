import Foundation
import AppKit
import SwiftUI
import Combine

final class MemoStore: ObservableObject {
    static let directoryName = "MemontoMori"
    static let supportedExtensions: Set<String> = ["txt", "md"]

    private static let intervalKey = "memontoMori.rotationInterval"
    private static let idleKey = "memontoMori.idleTimeout"
    private static let subdirKey = "memontoMori.currentSubdirectory"

    private static func entriesKey(for subdir: String) -> String {
        subdir.isEmpty ? "memontoMori.entries" : "memontoMori.entries.\(subdir)"
    }

    private static func lastIDKey(for subdir: String) -> String {
        subdir.isEmpty ? "memontoMori.lastDisplayedID" : "memontoMori.lastDisplayedID.\(subdir)"
    }

    @Published private(set) var entries: [MemoEntry] = []
    @Published private(set) var availableSubdirectories: [String] = []

    @Published var rotationInterval: TimeInterval {
        didSet { UserDefaults.standard.set(rotationInterval, forKey: Self.intervalKey) }
    }

    @Published var idleTimeout: TimeInterval {
        didSet { UserDefaults.standard.set(idleTimeout, forKey: Self.idleKey) }
    }

    @Published var lastDisplayedID: String? {
        didSet {
            UserDefaults.standard.set(lastDisplayedID, forKey: Self.lastIDKey(for: currentSubdirectory))
        }
    }

    @Published private(set) var currentSubdirectory: String {
        didSet { UserDefaults.standard.set(currentSubdirectory, forKey: Self.subdirKey) }
    }

    let rootDirectoryURL: URL

    var directoryURL: URL {
        currentSubdirectory.isEmpty
            ? rootDirectoryURL
            : rootDirectoryURL.appendingPathComponent(currentSubdirectory, isDirectory: true)
    }

    private var pendingWrites: [String: String] = [:]
    private var debounceTask: Task<Void, Never>?

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        let root = documents.appendingPathComponent(Self.directoryName, isDirectory: true)
        self.rootDirectoryURL = root

        let defaults = UserDefaults.standard
        self.rotationInterval = (defaults.object(forKey: Self.intervalKey) as? TimeInterval) ?? 600
        self.idleTimeout = (defaults.object(forKey: Self.idleKey) as? TimeInterval) ?? 600

        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let dirs = Self.scanSubdirectories(root: root)
        var storedSubdir = defaults.string(forKey: Self.subdirKey) ?? ""
        if !storedSubdir.isEmpty && !dirs.contains(storedSubdir) {
            storedSubdir = ""
        }

        self.availableSubdirectories = dirs
        self.currentSubdirectory = storedSubdir
        self.lastDisplayedID = defaults.string(forKey: Self.lastIDKey(for: storedSubdir))

        ensureDirectoryExists()
        rescan()
    }

    func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func rescan() {
        try? FileManager.default.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        refreshAvailableSubdirectories()

        // フォルダが Finder などで削除された場合はルートにフォールバックする
        if !currentSubdirectory.isEmpty && !availableSubdirectories.contains(currentSubdirectory) {
            currentSubdirectory = ""
            lastDisplayedID = UserDefaults.standard.string(forKey: Self.lastIDKey(for: ""))
        }

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

    // MARK: - Subdirectories

    func selectSubdirectory(_ relativePath: String) {
        let target = relativePath
        if target == currentSubdirectory { return }
        if !target.isEmpty && !availableSubdirectories.contains(target) { return }

        flushPending()
        currentSubdirectory = target
        ensureDirectoryExists()
        lastDisplayedID = UserDefaults.standard.string(forKey: Self.lastIDKey(for: target))
        rescan()
    }

    @discardableResult
    func createSubdirectory(name: String) -> Result<String, Error> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(MemoStoreError.emptyName)
        }
        guard !trimmed.contains("/"), !trimmed.contains("\\"),
              trimmed != ".", trimmed != "..", !trimmed.hasPrefix(".") else {
            return .failure(MemoStoreError.invalidName)
        }

        let parent = directoryURL
        let url = parent.appendingPathComponent(trimmed, isDirectory: true)
        if FileManager.default.fileExists(atPath: url.path) {
            return .failure(MemoStoreError.alreadyExists)
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            refreshAvailableSubdirectories()
            let newRel = currentSubdirectory.isEmpty ? trimmed : currentSubdirectory + "/" + trimmed
            selectSubdirectory(newRel)
            return .success(newRel)
        } catch {
            return .failure(error)
        }
    }

    func refreshAvailableSubdirectories() {
        availableSubdirectories = Self.scanSubdirectories(root: rootDirectoryURL)
    }

    private static func scanSubdirectories(root: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let rootPath = root.standardizedFileURL.path
        var result: [String] = []
        for case let url as URL in enumerator {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(rootPath) else { continue }
            var rel = String(path.dropFirst(rootPath.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            if !rel.isEmpty {
                result.append(rel)
            }
        }
        result.sort()
        return result
    }

    private func loadStoredEntries() -> [MemoEntry] {
        guard let data = UserDefaults.standard.data(forKey: Self.entriesKey(for: currentSubdirectory)),
              let decoded = try? JSONDecoder().decode([MemoEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveEntries() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.entriesKey(for: currentSubdirectory))
        }
    }
}

enum MemoStoreError: LocalizedError {
    case emptyName
    case invalidName
    case alreadyExists

    var errorDescription: String? {
        switch self {
        case .emptyName: return "名前が空です"
        case .invalidName: return "名前に / や . から始まる名前は使えません"
        case .alreadyExists: return "同名の項目がすでに存在します"
        }
    }
}
