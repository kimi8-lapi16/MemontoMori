import SwiftUI
import AppKit

/// ⌘P / ⇧⌘P で開く、VS Code 風のコマンドパレット。
///
/// - 入力欄がそのままのとき: ルート配下のメモとフォルダを fzf のように絞り込む。
/// - 入力欄が `>` で始まるとき: コマンド一覧を絞り込んで実行する。
///
/// 作成・リネーム・削除は、パレットを閉じずに **名前入力 / 確認** の段階へ進む形にしている。
/// 別のシートを重ねるより、キーボードだけで完結するほうがパレットらしいため。
struct CommandPalette: View {
    @ObservedObject var store: MemoStore
    @ObservedObject var rotation: RotationController

    @State private var query: String = ""
    @State private var inputText: String = ""
    @State private var selection: Int = 0
    @State private var stage: PaletteStage = .picking
    @State private var errorMessage: String?

    /// 一度に描く候補の上限。メモが増えても入力のたびに全件描かないようにする。
    private static let maxRows = 200
    private static let rowHeight: CGFloat = 42
    private static let listMaxHeight: CGFloat = 340

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.2)
                .contentShape(Rectangle())
                .onTapGesture { close() }

            panel
                .frame(width: 560)
                .padding(.top, 64)
        }
        .ignoresSafeArea()
        .onAppear { prepare(for: store.paletteMode) }
        .onChange(of: store.paletteMode) { _, mode in prepare(for: mode) }
        .onChange(of: query) { _, _ in
            selection = 0
            errorMessage = nil
        }
        .onChange(of: inputText) { _, _ in errorMessage = nil }
    }

    // MARK: - パネル

    private var panel: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: Color.black.opacity(0.28), radius: 24, y: 10)
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .picking:
            pickingContent
        case let .input(kind):
            inputContent(kind)
        case let .confirm(kind):
            confirmContent(kind)
        }
    }

    // MARK: - 絞り込み

    private var pickingContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: isCommandMode ? "chevron.right" : "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                PaletteTextField(
                    text: $query,
                    placeholder: isCommandMode
                        ? "コマンド名を入力"
                        : "ファイル名・フォルダ名を入力（先頭に > でコマンド）",
                    onMove: moveSelection(by:),
                    onSubmit: { activate(at: selection) },
                    onCancel: close,
                    onComplete: completeSelection
                )
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            errorBar

            Divider()
            resultList
            Divider()

            hintBar(
                hints: [
                    KeyHint(keys: "↑↓", description: "移動"),
                    KeyHint(keys: "Tab", description: "取り込み"),
                    KeyHint(keys: "Enter", description: "決定"),
                    KeyHint(keys: "Esc", description: "閉じる")
                ],
                trailing: isCommandMode ? "コマンド" : "ファイル / フォルダ"
            )
        }
    }

    private var resultList: some View {
        let rows = self.rows
        return Group {
            if rows.isEmpty {
                Text(isCommandMode ? "一致するコマンドがありません" : "一致するファイル・フォルダがありません")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                rowView(row, isSelected: index == selection)
                                    .id(row.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { activate(at: index) }
                            }
                        }
                        .padding(6)
                    }
                    .frame(
                        height: min(
                            CGFloat(rows.count) * Self.rowHeight + 12,
                            Self.listMaxHeight
                        )
                    )
                    .onChange(of: selection) { _, index in
                        guard rows.indices.contains(index) else { return }
                        proxy.scrollTo(rows[index].id, anchor: .center)
                    }
                }
            }
        }
    }

    private func rowView(_ row: PaletteRow, isSelected: Bool) -> some View {
        let base: Color = isSelected ? Color.white : Color.primary
        let subtitleBase: Color = isSelected ? Color.white.opacity(0.8) : Color.secondary
        let accent: Color = isSelected ? Color.white : Color.accentColor

        return HStack(spacing: 10) {
            Image(systemName: row.systemImage)
                .font(.system(size: 12))
                .foregroundColor(isSelected ? Color.white : Color.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                highlighted(
                    row.title,
                    indices: row.titleHighlight,
                    size: 13,
                    base: base,
                    accent: accent
                )
                .lineLimit(1)
                .truncationMode(.middle)

                if !row.subtitle.isEmpty {
                    highlighted(
                        row.subtitle,
                        indices: row.subtitleHighlight,
                        size: 11,
                        base: subtitleBase,
                        accent: accent
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            if let trailing = row.trailing {
                Text(trailing)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(isSelected ? Color.white.opacity(0.85) : Color.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight - 6, alignment: .leading)
        .background(isSelected ? Color.accentColor : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    /// 一致した文字だけ太字＋アクセント色にする。
    /// `Text` の連結で作るので、外から `foregroundColor` を上書きしないこと。
    private func highlighted(
        _ string: String,
        indices: [Int],
        size: CGFloat,
        base: Color,
        accent: Color
    ) -> Text {
        let characters = Array(string)
        let marked = Set(indices.filter { $0 >= 0 && $0 < characters.count })
        guard !marked.isEmpty else {
            return Text(string).font(.system(size: size)).foregroundColor(base)
        }

        var result = Text("")
        var buffer = ""
        var bufferMarked = false

        func flush() {
            guard !buffer.isEmpty else { return }
            result = result + Text(buffer)
                .font(.system(size: size))
                .fontWeight(bufferMarked ? .semibold : .regular)
                .foregroundColor(bufferMarked ? accent : base)
            buffer = ""
        }

        for (index, character) in characters.enumerated() {
            let isMarked = marked.contains(index)
            if isMarked != bufferMarked {
                flush()
                bufferMarked = isMarked
            }
            buffer.append(character)
        }
        flush()
        return result
    }

    // MARK: - 名前入力（作成・リネーム）

    private func inputContent(_ kind: PaletteInput) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                PaletteTextField(
                    text: $inputText,
                    placeholder: kind.placeholder,
                    onMove: { _ in },
                    onSubmit: { submit(kind) },
                    onCancel: close,
                    onComplete: {}
                )
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            errorBar

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text(kind.title)
                    .font(.system(size: 12, weight: .medium))
                Text(kind.caption(currentFolder: store.currentSubdirectory))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)

            Divider()

            hintBar(
                hints: [
                    KeyHint(keys: "Enter", description: "確定"),
                    KeyHint(keys: "Esc", description: "キャンセル")
                ],
                trailing: nil
            )
        }
    }

    // MARK: - 削除の確認

    private func confirmContent(_ kind: PaletteConfirm) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
                Text(kind.title)
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(kind.caption)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("キャンセル") { close() }
                    .keyboardShortcut(.cancelAction)
                Button("ゴミ箱へ", role: .destructive) { submit(kind) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    // MARK: - 共通パーツ

    @ViewBuilder
    private var errorBar: some View {
        if let errorMessage {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(errorMessage)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11))
            .foregroundColor(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private func hintBar(hints: [KeyHint], trailing: String?) -> some View {
        HStack(spacing: 12) {
            ForEach(hints) { hint in
                HStack(spacing: 4) {
                    Text(hint.keys)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.08))
                        )
                    Text(hint.description)
                }
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
            }
        }
        .font(.system(size: 10))
        .foregroundColor(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 26)
    }

    // MARK: - 候補の組み立て

    private var isCommandMode: Bool { query.hasPrefix(">") }

    private var trimmedQuery: String {
        let raw = isCommandMode ? String(query.dropFirst()) : query
        return raw.trimmingCharacters(in: .whitespaces)
    }

    private var rows: [PaletteRow] {
        isCommandMode ? commandRows : fileRows
    }

    private var fileRows: [PaletteRow] {
        let keyword = trimmedQuery
        var rows: [PaletteRow] = []

        let memos = store.allMemos
        for (order, memo) in memos.enumerated() {
            if let row = memoRow(memo, keyword: keyword, order: order) {
                rows.append(row)
            }
        }
        for (offset, folder) in store.allFolders.enumerated() {
            if let row = folderRow(folder, keyword: keyword, order: memos.count + offset) {
                rows.append(row)
            }
        }

        if keyword.isEmpty {
            // 入力前は、いま開いているフォルダの中身を上に出す。
            rows.sort { lhs, rhs in
                if lhs.isCurrentFolder != rhs.isCurrentFolder { return lhs.isCurrentFolder }
                return lhs.order < rhs.order
            }
        } else {
            rows.sort { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.order < rhs.order
            }
        }
        return Array(rows.prefix(Self.maxRows))
    }

    private func memoRow(_ memo: MemoLocation, keyword: String, order: Int) -> PaletteRow? {
        // フォルダ名でも引けるよう、照合はルートからの相対パス全体に対して行う。
        guard let match = FuzzyMatcher.match(query: keyword, in: memo.path) else { return nil }

        let folderLength = memo.folder.isEmpty ? 0 : memo.folder.count + 1
        let titleHighlight = match.matchedIndices
            .filter { $0 >= folderLength }
            .map { $0 - folderLength }
        let subtitleHighlight = match.matchedIndices.filter { $0 < max(folderLength - 1, 0) }

        var score = match.score
        // ファイル名だけに当たったものを上に出す。
        if !keyword.isEmpty && subtitleHighlight.isEmpty { score += 30 }
        let isCurrentFolder = memo.folder == store.currentSubdirectory
        if isCurrentFolder { score += 8 }

        return PaletteRow(
            id: "memo:" + memo.path,
            payload: .memo(memo),
            title: memo.name,
            titleHighlight: titleHighlight,
            subtitle: memo.folder.isEmpty ? "（ルート）" : memo.folder,
            subtitleHighlight: memo.folder.isEmpty ? [] : subtitleHighlight,
            systemImage: Self.icon(for: memo.name),
            trailing: nil,
            score: score,
            order: order,
            isCurrentFolder: isCurrentFolder
        )
    }

    private func folderRow(_ folder: String, keyword: String, order: Int) -> PaletteRow? {
        let label = folder.isEmpty ? MemoStore.directoryName : folder
        guard let match = FuzzyMatcher.match(query: keyword, in: label) else { return nil }

        let leaf = folder.isEmpty ? MemoStore.directoryName : FolderNode.leafName(of: folder)
        let parentLength = label.count - leaf.count
        let parent = String(label.dropLast(leaf.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let titleHighlight = match.matchedIndices
            .filter { $0 >= parentLength }
            .map { $0 - parentLength }

        // 同じスコアならメモを先に出す（探しものはたいていファイルなので）。
        var score = match.score - 5
        let isCurrentFolder = folder == store.currentSubdirectory
        if isCurrentFolder { score += 8 }

        return PaletteRow(
            id: "folder:" + folder,
            payload: .folder(folder),
            title: leaf,
            titleHighlight: titleHighlight,
            subtitle: parent.isEmpty ? "\(store.memoCount(in: folder)) 件のメモ" : parent,
            subtitleHighlight: parent.isEmpty ? [] : match.matchedIndices.filter { $0 < parent.count },
            systemImage: folder.isEmpty ? "house" : "folder",
            trailing: "フォルダ",
            score: score,
            order: order,
            isCurrentFolder: isCurrentFolder
        )
    }

    private var commandRows: [PaletteRow] {
        let keyword = trimmedQuery
        var rows: [PaletteRow] = []

        for (order, descriptor) in CommandCatalog.all.enumerated() {
            guard isAvailable(descriptor.id) else { continue }

            var score = 0
            var titleHighlight: [Int] = []
            if !keyword.isEmpty {
                guard let best = FuzzyMatcher.bestMatch(
                    query: keyword,
                    in: descriptor.searchTargets
                ) else { continue }
                score = best.match.score
                if best.index == 0 {
                    titleHighlight = best.match.matchedIndices
                } else {
                    // 別名（英語表記）に当たった場合は、位置が対応しないのでハイライトしない。
                    score -= 10
                }
            }

            rows.append(
                PaletteRow(
                    id: "command:" + descriptor.id.rawValue,
                    payload: .command(descriptor),
                    title: descriptor.title,
                    titleHighlight: titleHighlight,
                    subtitle: descriptor.summary,
                    subtitleHighlight: [],
                    systemImage: descriptor.systemImage,
                    trailing: descriptor.shortcut,
                    score: score,
                    order: order,
                    isCurrentFolder: false
                )
            )
        }

        rows.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.order < rhs.order
        }
        return rows
    }

    /// いま実行できないコマンドは一覧に出さない（押しても何も起きない項目を並べない）。
    private func isAvailable(_ id: CommandID) -> Bool {
        switch id {
        case .renameMemo, .deleteMemo, .revealMemo, .toggleRotationTarget:
            return currentMemo != nil
        case .togglePreview:
            guard let memo = currentMemo else { return false }
            return URL(fileURLWithPath: memo.name).pathExtension.lowercased() == "md"
        case .renameFolder, .deleteFolder:
            return !store.currentSubdirectory.isEmpty
        case .nextMemo, .previousMemo:
            return store.enabledEntries.count > 1
        case .searchFiles, .showCommands, .newMemo, .newFolder, .revealFolder,
             .rescan, .toggleRotation, .toggleSidebar, .togglePin, .openSettings:
            return true
        }
    }

    private var currentMemo: MemoLocation? {
        guard let id = rotation.currentID,
              store.entries.contains(where: { $0.id == id }) else { return nil }
        return MemoLocation(folder: store.currentSubdirectory, name: id)
    }

    private static func icon(for fileName: String) -> String {
        if MemoEntry.isImage(id: fileName) { return "photo" }
        return URL(fileURLWithPath: fileName).pathExtension.lowercased() == "md"
            ? "doc.richtext"
            : "doc.plaintext"
    }

    // MARK: - 操作

    private func prepare(for mode: PaletteMode?) {
        guard let mode else { return }
        errorMessage = nil
        selection = 0
        switch mode {
        case .files:
            stage = .picking
            query = ""
        case .commands:
            stage = .picking
            query = ">"
        case .newMemo:
            begin(.newMemo)
        case .newFolder:
            begin(.newFolder)
        }
    }

    private func moveSelection(by delta: Int) {
        let count = rows.count
        guard count > 0 else {
            selection = 0
            return
        }
        selection = ((selection + delta) % count + count) % count
    }

    /// Tab は選択中の候補を入力欄へ取り込む。fzf-tab のように、そこからさらに絞り込める。
    private func completeSelection() {
        let rows = self.rows
        guard rows.indices.contains(selection) else { return }
        switch rows[selection].payload {
        case let .memo(memo):
            query = memo.path
        case let .folder(folder):
            query = folder.isEmpty ? "" : folder + "/"
        case let .command(descriptor):
            query = ">" + descriptor.title
        }
        selection = 0
    }

    private func activate(at index: Int) {
        let rows = self.rows
        guard rows.indices.contains(index) else { return }
        switch rows[index].payload {
        case let .memo(memo):
            open(memo)
        case let .folder(folder):
            open(folder: folder)
        case let .command(descriptor):
            run(descriptor.id)
        }
    }

    private func open(_ memo: MemoLocation) {
        store.isShowingSettings = false
        if memo.folder != store.currentSubdirectory {
            store.selectSubdirectory(memo.folder)
            rotation.reconcile()
        }
        rotation.switchTo(id: memo.name)
        close()
    }

    private func open(folder: String) {
        store.isShowingSettings = false
        store.selectSubdirectory(folder)
        store.expandAncestors(of: folder)
        rotation.reconcile()
        close()
    }

    private func begin(_ kind: PaletteInput) {
        errorMessage = nil
        inputText = kind.initialText
        stage = .input(kind)
    }

    private func run(_ id: CommandID) {
        switch id {
        case .searchFiles:
            stage = .picking
            query = ""
            selection = 0
        case .showCommands:
            stage = .picking
            query = ">"
            selection = 0
        case .newMemo:
            begin(.newMemo)
        case .newFolder:
            begin(.newFolder)
        case .renameMemo:
            guard let memo = currentMemo else { return }
            begin(.renameMemo(memo))
        case .renameFolder:
            guard !store.currentSubdirectory.isEmpty else { return }
            begin(.renameFolder(store.currentSubdirectory))
        case .deleteMemo:
            guard let memo = currentMemo else { return }
            stage = .confirm(.deleteMemo(memo))
        case .deleteFolder:
            guard !store.currentSubdirectory.isEmpty else { return }
            stage = .confirm(.deleteFolder(store.currentSubdirectory))
        case .revealMemo:
            guard let memo = currentMemo else { return }
            store.revealInFinder(memoID: memo.name, in: memo.folder)
            close()
        case .revealFolder:
            store.revealInFinder(relativePath: store.currentSubdirectory)
            close()
        case .rescan:
            store.rescan()
            rotation.reconcile()
            close()
        case .nextMemo:
            rotation.advance(by: 1, userInitiated: true)
            close()
        case .previousMemo:
            rotation.advance(by: -1, userInitiated: true)
            close()
        case .toggleRotationTarget:
            guard let memo = currentMemo else { return }
            let entry = store.memos(in: memo.folder).first(where: { $0.id == memo.name })
            let isEnabled = entry?.isEnabled ?? true
            store.setEnabled(id: memo.name, in: memo.folder, enabled: !isEnabled)
            rotation.reconcile()
            close()
        case .toggleRotation:
            store.rotationEnabled.toggle()
            close()
        case .togglePreview:
            store.flushPending()
            store.isPreviewing.toggle()
            close()
        case .toggleSidebar:
            store.folderSidebarVisible.toggle()
            close()
        case .togglePin:
            store.isPinned.toggle()
            close()
        case .openSettings:
            store.flushPending()
            store.isShowingSettings = true
            close()
        }
    }

    private func submit(_ kind: PaletteInput) {
        switch kind {
        case .newMemo:
            switch store.createMemo(relativePath: inputText) {
            case let .success(memo):
                store.isShowingSettings = false
                rotation.reconcile()
                rotation.switchTo(id: memo.name)
                close()
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        case .newFolder:
            switch store.createFolder(relativePath: inputText) {
            case .success:
                store.isShowingSettings = false
                rotation.reconcile()
                close()
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        case let .renameMemo(memo):
            switch store.renameMemo(id: memo.name, in: memo.folder, to: inputText) {
            case let .success(renamed):
                rotation.reconcile()
                if renamed.folder == store.currentSubdirectory {
                    rotation.switchTo(id: renamed.name)
                }
                close()
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        case let .renameFolder(path):
            switch store.renameSubdirectory(path, to: inputText) {
            case .success:
                rotation.reconcile()
                close()
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func submit(_ kind: PaletteConfirm) {
        switch kind {
        case let .deleteMemo(memo):
            store.deleteMemo(id: memo.name, in: memo.folder)
        case let .deleteFolder(path):
            store.deleteSubdirectory(path)
        }
        rotation.reconcile()
        close()
    }

    private func close() {
        store.closePalette()
    }
}

// MARK: - 状態

private enum PaletteStage: Equatable {
    case picking
    case input(PaletteInput)
    case confirm(PaletteConfirm)
}

private enum PaletteInput: Equatable {
    case newMemo
    case newFolder
    case renameMemo(MemoLocation)
    case renameFolder(String)

    var initialText: String {
        switch self {
        case .newMemo, .newFolder: return ""
        case let .renameMemo(memo): return memo.name
        case let .renameFolder(path): return FolderNode.leafName(of: path)
        }
    }

    var title: String {
        switch self {
        case .newMemo: return "新規メモ"
        case .newFolder: return "新規フォルダ"
        case .renameMemo: return "メモの名前を変更"
        case .renameFolder: return "フォルダの名前を変更"
        }
    }

    var placeholder: String {
        switch self {
        case .newMemo: return "ファイル名（例: todo.md / work/todo）"
        case .newFolder: return "フォルダ名（例: work/2026）"
        case .renameMemo: return "新しいファイル名"
        case .renameFolder: return "新しいフォルダ名"
        }
    }

    var systemImage: String {
        switch self {
        case .newMemo: return "square.and.pencil"
        case .newFolder: return "folder.badge.plus"
        case .renameMemo: return "pencil.line"
        case .renameFolder: return "folder.badge.gearshape"
        }
    }

    func caption(currentFolder: String) -> String {
        let location = currentFolder.isEmpty ? "（ルート）" : currentFolder
        switch self {
        case .newMemo:
            return "作成先: \(location) / 拡張子を省略すると .md、"
                + "work/todo のように書くと途中のフォルダも作られます（先頭の / はルート起点）。"
        case .newFolder:
            return "作成先: \(location) / a/b のように書くと階層をまとめて作れます（先頭の / はルート起点）。"
        case let .renameMemo(memo):
            return "対象: \(memo.path) / 拡張子を省略すると元のままです。"
                + "並び順とローテーション対象の設定は引き継がれます。"
        case let .renameFolder(path):
            return "対象: \(path) / 中のメモの並び順や展開状態もそのまま移ります。"
        }
    }
}

private enum PaletteConfirm: Equatable {
    case deleteMemo(MemoLocation)
    case deleteFolder(String)

    var title: String {
        switch self {
        case .deleteMemo: return "メモをゴミ箱へ移動しますか？"
        case .deleteFolder: return "フォルダをゴミ箱へ移動しますか？"
        }
    }

    var caption: String {
        switch self {
        case let .deleteMemo(memo):
            return "「\(memo.path)」をゴミ箱に移動します。"
        case let .deleteFolder(path):
            return "「\(path)」を中のメモやサブフォルダごとゴミ箱に移動します。"
        }
    }
}

private struct PaletteRow: Identifiable {
    enum Payload {
        case memo(MemoLocation)
        case folder(String)
        case command(CommandDescriptor)
    }

    let id: String
    let payload: Payload
    let title: String
    /// `title` の何文字目を光らせるか。
    let titleHighlight: [Int]
    let subtitle: String
    let subtitleHighlight: [Int]
    let systemImage: String
    /// 右端に薄く出す補足（ショートカットなど）。
    let trailing: String?
    let score: Int
    /// 同点だったときの安定した並び順。
    let order: Int
    let isCurrentFolder: Bool
}

// MARK: - 入力欄

/// パレットの入力欄。
///
/// SwiftUI の `TextField` だと ↑↓ や Tab を横取りできないため、`NSTextField` を包んで
/// `doCommandBy` でキー操作を拾っている。⌃P / ⌃N も macOS の標準キーバインドとして
/// `moveUp:` / `moveDown:` に落ちてくるので、そのまま候補移動になる。
private struct PaletteTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onComplete: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 15)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.isAutomaticTextCompletionEnabled = false

        // ウィンドウに載ってからでないと first responder になれない。
        DispatchQueue.main.async {
            guard let window = field.window else { return }
            context.coordinator.rememberResponder(of: window, excluding: field)
            window.makeFirstResponder(field)
            field.currentEditor()?.selectedRange = NSRange(
                location: (text as NSString).length,
                length: 0
            )
        }
        return field
    }

    /// パレットを閉じたあと、そのまま本文の編集に戻れるようフォーカスを返す。
    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        guard let window = nsView.window,
              let previous = coordinator.previousResponder else { return }
        DispatchQueue.main.async { [weak window, weak previous] in
            guard let window, let previous else { return }
            // 入力欄の差し替え中など、すでに誰かがフォーカスを取っていたら触らない。
            // ビューが外れた直後の first responder はウィンドウ自身になる。
            guard window.firstResponder === window else { return }
            window.makeFirstResponder(previous)
        }
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        nsView.placeholderString = placeholder
        if nsView.stringValue != text {
            nsView.stringValue = text
            // 外から書き換えた（> を差し込んだ等）ときはカーソルを末尾に置く。
            nsView.currentEditor()?.selectedRange = NSRange(
                location: (text as NSString).length,
                length: 0
            )
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PaletteTextField
        /// パレットを開く前にフォーカスを持っていたビュー（たいていは本文のエディタ）。
        private(set) weak var previousResponder: NSResponder?

        init(parent: PaletteTextField) {
            self.parent = parent
        }

        func rememberResponder(of window: NSWindow, excluding field: NSTextField) {
            guard previousResponder == nil else { return }
            guard let current = window.firstResponder, current !== field else { return }
            // NSTextField にフォーカスがあるときの first responder はウィンドウ共用の
            // フィールドエディタなので、それを覚えても戻す先にはならない。
            if let textView = current as? NSTextView, textView.isFieldEditor { return }
            previousResponder = current
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.insertTab(_:)):
                parent.onComplete()
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                parent.onMove(-1)
                return true
            default:
                return false
            }
        }
    }
}
