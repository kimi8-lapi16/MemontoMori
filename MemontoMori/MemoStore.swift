import Foundation
import AppKit
import SwiftUI
import Combine

final class MemoStore: ObservableObject {
    static let directoryName = "MemontoMori"
    static let textExtensions: Set<String> = ["txt", "md"]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp"]
    static var supportedExtensions: Set<String> { textExtensions.union(imageExtensions) }

    private static let intervalKey = "memontoMori.rotationInterval"
    private static let idleKey = "memontoMori.idleTimeout"
    private static let subdirKey = "memontoMori.currentSubdirectory"
    private static let rotationEnabledKey = "memontoMori.rotationEnabled"
    private static let imageTransitionKey = "memontoMori.imageTransition"
    private static let sidebarVisibleKey = "memontoMori.folderSidebarVisible"
    private static let sidebarWidthKey = "memontoMori.folderSidebarWidth"
    private static let expandedFoldersKey = "memontoMori.expandedFolders"

    static let defaultSidebarWidth: Double = 200
    static let minSidebarWidth: Double = 140
    static let maxSidebarWidth: Double = 400

    private static func entriesKey(for subdir: String) -> String {
        subdir.isEmpty ? "memontoMori.entries" : "memontoMori.entries.\(subdir)"
    }

    private static func lastIDKey(for subdir: String) -> String {
        subdir.isEmpty ? "memontoMori.lastDisplayedID" : "memontoMori.lastDisplayedID.\(subdir)"
    }

    @Published private(set) var entries: [MemoEntry] = []
    @Published private(set) var availableSubdirectories: [String] = []

    /// フォルダごとのメモ一覧。キーはルートからの相対パス（ルートは空文字）。
    /// 左ペインではどのフォルダも開閉して中身を見られるので、選択中フォルダ以外のぶんも持つ。
    /// 並び順・有効状態はフォルダごとに `UserDefaults` へ保存したものを反映している。
    @Published private(set) var folderEntries: [String: [MemoEntry]] = [:]

    @Published var rotationInterval: TimeInterval {
        didSet { UserDefaults.standard.set(rotationInterval, forKey: Self.intervalKey) }
    }

    @Published var idleTimeout: TimeInterval {
        didSet { UserDefaults.standard.set(idleTimeout, forKey: Self.idleKey) }
    }

    @Published var rotationEnabled: Bool {
        didSet { UserDefaults.standard.set(rotationEnabled, forKey: Self.rotationEnabledKey) }
    }

    @Published var imageTransition: ImageTransitionStyle {
        didSet { UserDefaults.standard.set(imageTransition.rawValue, forKey: Self.imageTransitionKey) }
    }

    @Published var lastDisplayedID: String? {
        didSet {
            UserDefaults.standard.set(lastDisplayedID, forKey: Self.lastIDKey(for: currentSubdirectory))
        }
    }

    @Published private(set) var currentSubdirectory: String {
        didSet { UserDefaults.standard.set(currentSubdirectory, forKey: Self.subdirKey) }
    }

    /// 本文エリアを設定ページに切り替えているか。
    /// VS Code の設定タブと同じく開きっぱなしにするものではないので永続化しない。
    @Published var isShowingSettings: Bool = false

    /// 左ペイン（フォルダツリー）を表示するか。
    @Published var folderSidebarVisible: Bool {
        didSet { UserDefaults.standard.set(folderSidebarVisible, forKey: Self.sidebarVisibleKey) }
    }

    /// 左ペインの幅。ドラッグで変えられるので永続化する。
    @Published private(set) var folderSidebarWidth: Double {
        didSet { UserDefaults.standard.set(folderSidebarWidth, forKey: Self.sidebarWidthKey) }
    }

    /// 左ペインで開いた状態にしているフォルダの相対パス。
    @Published private(set) var expandedFolders: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(expandedFolders), forKey: Self.expandedFoldersKey)
        }
    }

    let rootDirectoryURL: URL

    var directoryURL: URL {
        currentSubdirectory.isEmpty
            ? rootDirectoryURL
            : rootDirectoryURL.appendingPathComponent(currentSubdirectory, isDirectory: true)
    }

    /// 走査で見つかったフォルダごとのファイル名。`folderEntries` を組み立てる材料。
    private var folderMemoNames: [String: [String]] = [:]

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
        self.rotationEnabled = (defaults.object(forKey: Self.rotationEnabledKey) as? Bool) ?? true
        self.imageTransition = defaults.string(forKey: Self.imageTransitionKey)
            .flatMap(ImageTransitionStyle.init(rawValue:)) ?? .fade
        self.folderSidebarVisible = (defaults.object(forKey: Self.sidebarVisibleKey) as? Bool) ?? true
        self.folderSidebarWidth = Self.clampSidebarWidth(
            (defaults.object(forKey: Self.sidebarWidthKey) as? Double) ?? Self.defaultSidebarWidth
        )
        self.expandedFolders = Set(defaults.stringArray(forKey: Self.expandedFoldersKey) ?? [])

        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let scan = Self.scanFolders(root: root)
        var storedSubdir = defaults.string(forKey: Self.subdirKey) ?? ""
        if !storedSubdir.isEmpty && !scan.paths.contains(storedSubdir) {
            storedSubdir = ""
        }

        self.availableSubdirectories = scan.paths
        self.folderMemoNames = scan.memoNames
        self.currentSubdirectory = storedSubdir
        self.lastDisplayedID = defaults.string(forKey: Self.lastIDKey(for: storedSubdir))

        expandAncestors(of: storedSubdir)
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

        var rebuilt: [String: [MemoEntry]] = [:]
        for (folder, names) in folderMemoNames {
            rebuilt[folder] = Self.merge(
                stored: loadStoredEntries(for: folder),
                presentNames: Set(names)
            )
        }
        // メモが 0 件のフォルダもキーは作っておく（現在フォルダの参照を空振りさせない）
        if rebuilt[currentSubdirectory] == nil {
            rebuilt[currentSubdirectory] = []
        }

        folderEntries = rebuilt
        entries = rebuilt[currentSubdirectory] ?? []
        saveEntries(entries, for: currentSubdirectory)
    }

    /// 保存済みの並び順・有効状態と、実在するファイルを突き合わせる。
    /// 消えたファイルは落とし、新しいファイルは名前順で末尾に足す。
    private static func merge(stored: [MemoEntry], presentNames: Set<String>) -> [MemoEntry] {
        var ordered = stored.filter { presentNames.contains($0.id) }
        let knownIDs = Set(ordered.map(\.id))
        for name in presentNames.subtracting(knownIDs).sorted() {
            ordered.append(MemoEntry(id: name, isEnabled: true))
        }
        return ordered
    }

    func memos(in subdirectory: String) -> [MemoEntry] {
        folderEntries[subdirectory] ?? []
    }

    func memoCount(in subdirectory: String) -> Int {
        folderEntries[subdirectory]?.count ?? 0
    }

    func setEnabled(id: String, enabled: Bool) {
        setEnabled(id: id, in: currentSubdirectory, enabled: enabled)
    }

    func setEnabled(id: String, in subdirectory: String, enabled: Bool) {
        var list = memos(in: subdirectory)
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        list[idx].isEnabled = enabled
        apply(list, for: subdirectory)
    }

    /// `id` のメモを `targetID` の位置へ移す。左ペインのドラッグ並べ替え用。
    func moveMemo(id: String, before targetID: String, in subdirectory: String) {
        var list = memos(in: subdirectory)
        guard let from = list.firstIndex(where: { $0.id == id }),
              let to = list.firstIndex(where: { $0.id == targetID }),
              from != to else { return }
        let moved = list.remove(at: from)
        list.insert(moved, at: to)
        apply(list, for: subdirectory)
    }

    /// `offset` ぶん上下に動かす。右クリックメニューからの 1 つ移動用。
    func moveMemo(id: String, by offset: Int, in subdirectory: String) {
        var list = memos(in: subdirectory)
        guard let from = list.firstIndex(where: { $0.id == id }) else { return }
        let to = from + offset
        guard list.indices.contains(to) else { return }
        let moved = list.remove(at: from)
        list.insert(moved, at: to)
        apply(list, for: subdirectory)
    }

    /// 並び順・有効状態の更新をまとめて反映する唯一の窓口。
    private func apply(_ list: [MemoEntry], for subdirectory: String) {
        folderEntries[subdirectory] = list
        if subdirectory == currentSubdirectory {
            entries = list
        }
        saveEntries(list, for: subdirectory)
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
        deleteMemo(id: id, in: currentSubdirectory)
    }

    func deleteMemo(id: String, in subdirectory: String) {
        if subdirectory == currentSubdirectory {
            flushPending(id: id)
        }
        let target = url(forRelativePath: subdirectory).appendingPathComponent(id)
        var resultingURL: NSURL?
        try? FileManager.default.trashItem(at: target, resultingItemURL: &resultingURL)
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

    func revealInFinder(relativePath: String) {
        let target = url(forRelativePath: relativePath)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        NSWorkspace.shared.open(target)
    }

    /// メモ本体を Finder で選択状態にして表示する。
    func revealInFinder(memoID: String, in subdirectory: String) {
        let target = url(forRelativePath: subdirectory).appendingPathComponent(memoID)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    func url(forRelativePath relativePath: String) -> URL {
        relativePath.isEmpty
            ? rootDirectoryURL
            : rootDirectoryURL.appendingPathComponent(relativePath, isDirectory: true)
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
        expandAncestors(of: target)
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

    /// フォルダを中身ごとゴミ箱へ移す。ルートは消させない。
    func deleteSubdirectory(_ relativePath: String) {
        guard !relativePath.isEmpty else { return }

        if currentSubdirectory == relativePath || currentSubdirectory.hasPrefix(relativePath + "/") {
            // 消えるフォルダに書き戻さないよう、保留中の書き込みは捨てる
            pendingWrites.removeAll()
            debounceTask?.cancel()
        } else {
            flushPending()
        }

        let target = url(forRelativePath: relativePath)
        var resultingURL: NSURL?
        try? FileManager.default.trashItem(at: target, resultingItemURL: &resultingURL)

        // 選択中フォルダが消えた場合のルートへのフォールバックは rescan() が行う
        rescan()
    }

    func refreshAvailableSubdirectories() {
        let scan = Self.scanFolders(root: rootDirectoryURL)
        availableSubdirectories = scan.paths
        folderMemoNames = scan.memoNames

        // 消えたフォルダの展開状態を残さない
        let valid = Set(availableSubdirectories)
        let pruned = expandedFolders.intersection(valid)
        if pruned != expandedFolders {
            expandedFolders = pruned
        }
    }

    // MARK: - Folder sidebar

    func setFolderSidebarWidth(_ width: Double) {
        let clamped = Self.clampSidebarWidth(width)
        if clamped != folderSidebarWidth {
            folderSidebarWidth = clamped
        }
    }

    static func clampSidebarWidth(_ width: Double) -> Double {
        min(max(width, minSidebarWidth), maxSidebarWidth)
    }

    func isExpanded(_ relativePath: String) -> Bool {
        // ルートは常に開いた状態として扱う
        relativePath.isEmpty || expandedFolders.contains(relativePath)
    }

    func toggleExpansion(_ relativePath: String) {
        guard !relativePath.isEmpty else { return }
        if expandedFolders.contains(relativePath) {
            expandedFolders.remove(relativePath)
        } else {
            expandedFolders.insert(relativePath)
        }
    }

    /// 選択中フォルダが折りたたまれた枝の中に隠れないよう、祖先をまとめて開く。
    func expandAncestors(of relativePath: String) {
        guard !relativePath.isEmpty else { return }
        var accumulated: [String] = []
        var opened = expandedFolders
        for component in relativePath.split(separator: "/") {
            accumulated.append(String(component))
            opened.insert(accumulated.joined(separator: "/"))
        }
        if opened != expandedFolders {
            expandedFolders = opened
        }
    }

    /// ルート配下を 1 度だけ走査して、フォルダの相対パスとフォルダごとのファイル名を同時に集める。
    private static func scanFolders(root: URL) -> (paths: [String], memoNames: [String: [String]]) {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ([], [:])
        }
        let rootPath = root.standardizedFileURL.path
        var paths: [String] = []
        var memoNames: [String: [String]] = [:]
        for case let url as URL in enumerator {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(rootPath) else { continue }
            var rel = String(path.dropFirst(rootPath.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            guard !rel.isEmpty else { continue }

            if isDir {
                paths.append(rel)
            } else if supportedExtensions.contains(url.pathExtension.lowercased()) {
                let parent = rel.split(separator: "/").dropLast().joined(separator: "/")
                memoNames[parent, default: []].append(url.lastPathComponent)
            }
        }
        paths.sort()
        for (folder, names) in memoNames {
            memoNames[folder] = names.sorted()
        }
        return (paths, memoNames)
    }

    private func loadStoredEntries(for subdirectory: String) -> [MemoEntry] {
        guard let data = UserDefaults.standard.data(forKey: Self.entriesKey(for: subdirectory)),
              let decoded = try? JSONDecoder().decode([MemoEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveEntries(_ list: [MemoEntry], for subdirectory: String) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: Self.entriesKey(for: subdirectory))
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
