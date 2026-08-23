import Foundation
import AppKit
import SwiftUI
import Combine

/// 「どのフォルダのどのメモか」を 1 つにまとめた参照。
/// 左ペインとコマンドパレットが同じ形でメモを指せるように、ここで共有している。
struct MemoLocation: Identifiable, Hashable {
    /// ルートからの相対パス（ルート直下は空文字）。
    let folder: String
    /// 拡張子込みのファイル名。
    let name: String

    /// ルートから見た相対パス。検索や表示に使う。
    var path: String { folder.isEmpty ? name : folder + "/" + name }

    var id: String { path }
}

/// コマンドパレットをどの状態で開くか。
enum PaletteMode: String, Equatable {
    /// ファイル・フォルダの絞り込み検索。
    case files
    /// コマンドの絞り込み実行（入力欄が `>` で始まる状態）。
    case commands
    /// 新規メモの名前入力を開いた状態。
    case newMemo
    /// 新規フォルダの名前入力を開いた状態。
    case newFolder
}

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

    /// コマンドパレットを開いているか。`nil` は閉じている状態。
    /// メニュー（⌘P / ⇧⌘P）からも開けるよう、ビューではなくストアが持つ。
    @Published var paletteMode: PaletteMode?

    /// `.md` を編集ではなくプレビューで表示しているか。
    /// パレットからも切り替えられるようにビューの `@State` から移した。
    @Published var isPreviewing: Bool = false

    /// ウィンドウを常に最前面に出しているか。起動のたびに素の状態から始めたいので永続化しない。
    @Published var isPinned: Bool = false

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
        createMemo(relativePath: name).map(\.name)
    }

    /// パス付きでメモを作る。`work/todo.md` のように書くと、途中のフォルダも一緒に作る。
    ///
    /// - Parameter relativePath: 現在のフォルダから見た相対パス。`/` で始めるとルート起点。
    ///   拡張子を省略した場合は `.md` を補う。
    @discardableResult
    func createMemo(relativePath: String) -> Result<MemoLocation, Error> {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(MemoStoreError.emptyName) }

        var components = trimmed.split(separator: "/").map(String.init)
        guard let rawName = components.popLast() else { return .failure(MemoStoreError.emptyName) }
        guard Self.isValidComponent(rawName), components.allSatisfy(Self.isValidComponent) else {
            return .failure(MemoStoreError.invalidName)
        }

        let folder = resolvedFolder(base: trimmed, components: components)
        let fileName = Self.memoFileName(
            for: rawName,
            allowedExtensions: Self.textExtensions,
            fallbackExtension: "md"
        )
        let directory = url(forRelativePath: folder)
        let fileURL = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return .failure(MemoStoreError.alreadyExists)
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "".write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            return .failure(error)
        }

        // 途中のフォルダを作った可能性があるので、一覧を更新してから移動する。
        refreshAvailableSubdirectories()
        expandAncestors(of: folder)
        if folder == currentSubdirectory {
            rescan()
        } else {
            selectSubdirectory(folder)
        }
        return .success(MemoLocation(folder: folder, name: fileName))
    }

    /// メモの名前を変える。並び順とローテーション対象の設定は引き継ぐ。
    ///
    /// - Parameter newName: 拡張子を省略した場合と、対応していない拡張子だった場合は
    ///   元の拡張子を補う（一覧から消えてしまわないようにするため）。
    @discardableResult
    func renameMemo(id: String, in subdirectory: String, to newName: String) -> Result<MemoLocation, Error> {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(MemoStoreError.emptyName) }
        guard !trimmed.contains("/"), Self.isValidComponent(trimmed) else {
            return .failure(MemoStoreError.invalidName)
        }

        // リネームでは画像の拡張子も残せるようにする。
        let fileName = Self.memoFileName(
            for: trimmed,
            allowedExtensions: Self.supportedExtensions,
            fallbackExtension: URL(fileURLWithPath: id).pathExtension
        )
        guard fileName != id else { return .success(MemoLocation(folder: subdirectory, name: id)) }

        let directory = url(forRelativePath: subdirectory)
        let source = directory.appendingPathComponent(id)
        let destination = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: source.path) else {
            return .failure(MemoStoreError.notFound)
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            return .failure(MemoStoreError.alreadyExists)
        }

        // 旧ファイル名で書き戻さないよう、保留中の内容を先に確定させる。
        if subdirectory == currentSubdirectory {
            flushPending(id: id)
        }
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            return .failure(error)
        }

        // 保存済みメタ情報の ID も差し替える。rescan() は UserDefaults を読み直すので、
        // ここで書いておかないと「消えた 1 件＋増えた 1 件」として末尾に回ってしまう。
        var list = memos(in: subdirectory)
        if let index = list.firstIndex(where: { $0.id == id }) {
            list[index].id = fileName
            apply(list, for: subdirectory)
        }

        let lastKey = Self.lastIDKey(for: subdirectory)
        if UserDefaults.standard.string(forKey: lastKey) == id {
            UserDefaults.standard.set(fileName, forKey: lastKey)
        }
        if subdirectory == currentSubdirectory, lastDisplayedID == id {
            lastDisplayedID = fileName
        }

        rescan()
        return .success(MemoLocation(folder: subdirectory, name: fileName))
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
        createFolder(relativePath: name)
    }

    /// パス付きでフォルダを作る。`work/2026/q1` のように階層をまとめて指定できる。
    ///
    /// - Parameter relativePath: 現在のフォルダから見た相対パス。`/` で始めるとルート起点。
    @discardableResult
    func createFolder(relativePath: String) -> Result<String, Error> {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(MemoStoreError.emptyName) }

        let components = trimmed.split(separator: "/").map(String.init)
        guard !components.isEmpty, components.allSatisfy(Self.isValidComponent) else {
            return .failure(MemoStoreError.invalidName)
        }

        let target = resolvedFolder(base: trimmed, components: components)
        let folderURL = url(forRelativePath: target)
        if FileManager.default.fileExists(atPath: folderURL.path) {
            return .failure(MemoStoreError.alreadyExists)
        }
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            return .failure(error)
        }
        refreshAvailableSubdirectories()
        selectSubdirectory(target)
        return .success(target)
    }

    /// フォルダの名前を変える。中のメモの並び順・有効状態・展開状態もそのまま移す。
    @discardableResult
    func renameSubdirectory(_ relativePath: String, to newName: String) -> Result<String, Error> {
        // ルートはアプリのメモ置き場そのものなので名前を変えさせない。
        guard !relativePath.isEmpty else { return .failure(MemoStoreError.invalidName) }

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(MemoStoreError.emptyName) }
        guard !trimmed.contains("/"), Self.isValidComponent(trimmed) else {
            return .failure(MemoStoreError.invalidName)
        }

        let parent = relativePath.split(separator: "/").dropLast().joined(separator: "/")
        let newPath = parent.isEmpty ? trimmed : parent + "/" + trimmed
        guard newPath != relativePath else { return .success(relativePath) }

        let source = url(forRelativePath: relativePath)
        let destination = url(forRelativePath: newPath)
        guard FileManager.default.fileExists(atPath: source.path) else {
            return .failure(MemoStoreError.notFound)
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            return .failure(MemoStoreError.alreadyExists)
        }

        flushPending()
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            return .failure(error)
        }

        // 配下のパスも巻き添えで変わるので、一覧を更新する前にメタ情報を移し替える。
        migrateFolderMetadata(from: relativePath, to: newPath)

        if currentSubdirectory == relativePath || currentSubdirectory.hasPrefix(relativePath + "/") {
            currentSubdirectory = newPath + String(currentSubdirectory.dropFirst(relativePath.count))
        }

        refreshAvailableSubdirectories()
        expandAncestors(of: currentSubdirectory)
        rescan()
        return .success(newPath)
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

    // MARK: - Naming helpers

    /// 相対パスの起点を決める。`/` 始まりならルート、そうでなければ現在のフォルダ。
    private func resolvedFolder(base: String, components: [String]) -> String {
        let root = base.hasPrefix("/") ? "" : currentSubdirectory
        return ([root] + components).filter { !$0.isEmpty }.joined(separator: "/")
    }

    /// パスの 1 階層ぶんとして使える名前か。`/` はここに来る前に分割済み。
    private static func isValidComponent(_ name: String) -> Bool {
        !name.isEmpty
            && !name.hasPrefix(".")
            && !name.contains("\\")
            && !name.contains(":")
    }

    /// 拡張子を省略した／その場面で使えない拡張子だった場合に補う。
    ///
    /// - Parameter allowedExtensions: そのまま通す拡張子。新規作成はテキストだけ（画像は
    ///   Finder から置く前提なので、空の画像ファイルを作らせない）、リネームは画像も含める。
    private static func memoFileName(
        for name: String,
        allowedExtensions: Set<String>,
        fallbackExtension: String
    ) -> String {
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        if allowedExtensions.contains(ext) { return name }
        let fallback = allowedExtensions.contains(fallbackExtension.lowercased())
            ? fallbackExtension
            : "md"
        return name + "." + fallback
    }

    /// フォルダのリネームに合わせて、そのフォルダと配下のメタ情報を新しいパスへ移す。
    /// `availableSubdirectories` を更新する **前** に呼ぶこと（旧パスの一覧が必要なため）。
    private func migrateFolderMetadata(from old: String, to new: String) {
        let defaults = UserDefaults.standard
        let affected = [old] + availableSubdirectories.filter { $0.hasPrefix(old + "/") }

        for path in affected {
            let moved = new + String(path.dropFirst(old.count))
            if let data = defaults.data(forKey: Self.entriesKey(for: path)) {
                defaults.set(data, forKey: Self.entriesKey(for: moved))
                defaults.removeObject(forKey: Self.entriesKey(for: path))
            }
            if let lastID = defaults.string(forKey: Self.lastIDKey(for: path)) {
                defaults.set(lastID, forKey: Self.lastIDKey(for: moved))
                defaults.removeObject(forKey: Self.lastIDKey(for: path))
            }
        }

        var opened = expandedFolders
        for path in affected where opened.contains(path) {
            opened.remove(path)
            opened.insert(new + String(path.dropFirst(old.count)))
        }
        if opened != expandedFolders {
            expandedFolders = opened
        }
    }

    // MARK: - Search

    /// ルート配下のすべてのメモ。コマンドパレットの検索対象。
    /// フォルダ順・フォルダ内はローテーション順で並べる。
    var allMemos: [MemoLocation] {
        folderEntries
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .flatMap { folder, list in
                list.map { MemoLocation(folder: folder, name: $0.id) }
            }
    }

    /// ルートを含むすべてのフォルダの相対パス。
    var allFolders: [String] {
        [""] + availableSubdirectories
    }

    // MARK: - Command palette

    func openPalette(_ mode: PaletteMode) {
        flushPending()
        paletteMode = mode
    }

    /// メニューから同じ項目をもう一度選んだときは閉じる。
    func togglePalette(_ mode: PaletteMode) {
        if paletteMode == mode {
            paletteMode = nil
        } else {
            openPalette(mode)
        }
    }

    func closePalette() {
        paletteMode = nil
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
    case notFound

    var errorDescription: String? {
        switch self {
        case .emptyName: return "名前が空です"
        case .invalidName: return "この名前は使えません（. で始まる名前や \\ : を含む名前は不可）"
        case .alreadyExists: return "同名の項目がすでに存在します"
        case .notFound: return "対象のファイルが見つかりません"
        }
    }
}
