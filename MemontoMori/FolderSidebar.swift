import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// メモの持ち物すべてを扱う左ペイン。
///
/// エディタや IDE のファイルツリーと同じく、どのフォルダも開閉して中身を確認でき、
/// フォルダ／メモの切り替え・作成・並べ替え・削除・Finder 表示をここに集約している。
struct FolderSidebar: View {
    @ObservedObject var store: MemoStore
    @ObservedObject var rotation: RotationController

    @State private var showingNewMemoSheet: Bool = false
    @State private var newMemoName: String = ""
    @State private var showingNewFolderSheet: Bool = false
    @State private var newFolderName: String = ""
    @State private var errorMessage: String?
    @State private var pendingDeleteMemo: MemoRef?
    @State private var pendingDeleteFolder: String?
    @State private var draggingMemo: MemoRef?

    private var rows: [SidebarRow] {
        FolderNode
            .build(
                rootName: MemoStore.directoryName,
                relativePaths: store.availableSubdirectories
            )
            .rows(
                isExpanded: { store.isExpanded($0) },
                memoCount: { store.memoCount(in: $0) },
                memos: { store.memos(in: $0) }
            )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(rows) { row in
                        rowView(for: row)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear { store.rescan() }
        .sheet(isPresented: $showingNewMemoSheet) {
            NameInputSheet(
                title: "新規メモ",
                caption: "拡張子を省略すると .md として作成されます。",
                locationLabel: currentLocationLabel,
                placeholder: "ファイル名",
                text: $newMemoName,
                onCancel: {
                    showingNewMemoSheet = false
                    newMemoName = ""
                },
                onCreate: createMemo
            )
        }
        .sheet(isPresented: $showingNewFolderSheet) {
            NameInputSheet(
                title: "新規フォルダ",
                caption: nil,
                locationLabel: currentLocationLabel,
                placeholder: "フォルダ名",
                text: $newFolderName,
                onCancel: {
                    showingNewFolderSheet = false
                    newFolderName = ""
                },
                onCreate: createFolder
            )
        }
        .alert(
            "メモを削除しますか？",
            isPresented: Binding(
                get: { pendingDeleteMemo != nil },
                set: { if !$0 { pendingDeleteMemo = nil } }
            ),
            presenting: pendingDeleteMemo
        ) { ref in
            Button("ゴミ箱へ", role: .destructive) {
                store.deleteMemo(id: ref.name, in: ref.folder)
                rotation.reconcile()
                pendingDeleteMemo = nil
            }
            Button("キャンセル", role: .cancel) { pendingDeleteMemo = nil }
        } message: { ref in
            Text("「\(MemoEntry.displayName(for: ref.name))」をゴミ箱に移動します。")
        }
        .alert(
            "フォルダを削除しますか？",
            isPresented: Binding(
                get: { pendingDeleteFolder != nil },
                set: { if !$0 { pendingDeleteFolder = nil } }
            ),
            presenting: pendingDeleteFolder
        ) { path in
            Button("ゴミ箱へ", role: .destructive) {
                store.deleteSubdirectory(path)
                rotation.reconcile()
                pendingDeleteFolder = nil
            }
            Button("キャンセル", role: .cancel) { pendingDeleteFolder = nil }
        } message: { path in
            Text("「\(FolderNode.leafName(of: path))」を中のメモやサブフォルダごとゴミ箱に移動します。")
        }
        .alert(
            "エラー",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 2) {
            Text("メモ")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            headerButton(systemImage: "square.and.pencil", help: "新規メモを作成") {
                beginCreateMemo(in: store.currentSubdirectory)
            }
            headerButton(systemImage: "folder.badge.plus", help: "新規フォルダを作成") {
                beginCreateFolder(in: store.currentSubdirectory)
            }
            headerButton(systemImage: "folder", help: "現在のフォルダを Finder で開く") {
                store.revealInFinder()
            }
            headerButton(systemImage: "arrow.clockwise", help: "再スキャン") {
                store.rescan()
                rotation.reconcile()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
    }

    private func headerButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    @ViewBuilder
    private func rowView(for row: SidebarRow) -> some View {
        switch row.kind {
        case let .folder(hasChildren, isRoot, memoCount):
            FolderRowView(
                name: row.name,
                depth: row.depth,
                hasChildren: hasChildren,
                isRoot: isRoot,
                memoCount: memoCount,
                isSelected: row.folderPath == store.currentSubdirectory,
                isExpanded: store.isExpanded(row.folderPath),
                helpText: isRoot ? "（ルート）" : row.folderPath,
                onSelect: { selectFolder(row.folderPath) },
                onToggleExpand: { store.toggleExpansion(row.folderPath) },
                onNewMemo: { beginCreateMemo(in: row.folderPath) },
                onNewFolder: { beginCreateFolder(in: row.folderPath) },
                onReveal: { store.revealInFinder(relativePath: row.folderPath) },
                canDelete: !isRoot,
                onDelete: { pendingDeleteFolder = row.folderPath }
            )
        case let .memo(isEnabled):
            let ref = MemoRef(folder: row.folderPath, name: row.name)
            MemoRowView(
                fileName: row.name,
                depth: row.depth,
                isEnabled: isEnabled,
                isCurrent: isCurrentMemo(ref),
                isDragging: draggingMemo == ref,
                canMoveUp: canMove(ref, by: -1),
                canMoveDown: canMove(ref, by: 1),
                onSelect: { openMemo(ref) },
                onToggleEnabled: {
                    store.setEnabled(id: ref.name, in: ref.folder, enabled: !isEnabled)
                    rotation.reconcile()
                },
                onMoveUp: { moveMemo(ref, by: -1) },
                onMoveDown: { moveMemo(ref, by: 1) },
                onReveal: { store.revealInFinder(memoID: ref.name, in: ref.folder) },
                onDelete: { pendingDeleteMemo = ref }
            )
            .onDrag {
                draggingMemo = ref
                return NSItemProvider(object: ref.name as NSString)
            }
            .onDrop(
                of: [UTType.text],
                delegate: MemoReorderDropDelegate(
                    target: ref,
                    dragging: $draggingMemo,
                    onReorder: { dragged, target in
                        store.moveMemo(id: dragged.name, before: target.name, in: target.folder)
                        rotation.reconcile()
                    }
                )
            )
        }
    }

    private var currentLocationLabel: String {
        store.currentSubdirectory.isEmpty ? "（ルート）" : store.currentSubdirectory
    }

    private func isCurrentMemo(_ ref: MemoRef) -> Bool {
        ref.folder == store.currentSubdirectory && ref.name == rotation.currentID
    }

    private func selectFolder(_ relativePath: String) {
        store.isShowingSettings = false
        if relativePath == store.currentSubdirectory {
            // 選択済みの行を押したときは開閉のトグルとして扱う（IDE と同じ感覚）
            store.toggleExpansion(relativePath)
            return
        }
        store.selectSubdirectory(relativePath)
        rotation.reconcile()
    }

    /// 別フォルダのメモを開くときは、そのフォルダをローテーション対象にしてから表示を移す。
    private func openMemo(_ ref: MemoRef) {
        store.isShowingSettings = false
        selectFolderIfNeeded(ref.folder)
        rotation.switchTo(id: ref.name)
    }

    private func canMove(_ ref: MemoRef, by offset: Int) -> Bool {
        let list = store.memos(in: ref.folder)
        guard let index = list.firstIndex(where: { $0.id == ref.name }) else { return false }
        return list.indices.contains(index + offset)
    }

    private func moveMemo(_ ref: MemoRef, by offset: Int) {
        store.moveMemo(id: ref.name, by: offset, in: ref.folder)
        rotation.reconcile()
    }

    /// 作成系はいずれも「現在のフォルダ」に作るので、別フォルダから呼ばれたらまず切り替える。
    private func beginCreateMemo(in relativePath: String) {
        selectFolderIfNeeded(relativePath)
        newMemoName = ""
        showingNewMemoSheet = true
    }

    private func beginCreateFolder(in relativePath: String) {
        selectFolderIfNeeded(relativePath)
        newFolderName = ""
        showingNewFolderSheet = true
    }

    private func selectFolderIfNeeded(_ relativePath: String) {
        guard relativePath != store.currentSubdirectory else { return }
        store.selectSubdirectory(relativePath)
        rotation.reconcile()
    }

    private func createMemo() {
        switch store.createMemo(name: newMemoName) {
        case .success(let fileName):
            showingNewMemoSheet = false
            newMemoName = ""
            store.isShowingSettings = false
            rotation.reconcile()
            // 作ったメモをすぐ書き始められるように表示を移す。
            rotation.switchTo(id: fileName)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func createFolder() {
        switch store.createSubdirectory(name: newFolderName) {
        case .success:
            showingNewFolderSheet = false
            newFolderName = ""
            rotation.reconcile()
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

/// 「どのフォルダのどのメモか」を 1 つにまとめた参照。
private struct MemoRef: Equatable {
    let folder: String
    let name: String
}

/// 行の上に別の行がドラッグされてきた時点で並べ替える、よくある方式のドロップ処理。
private struct MemoReorderDropDelegate: DropDelegate {
    let target: MemoRef
    @Binding var dragging: MemoRef?
    let onReorder: (MemoRef, MemoRef) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        // 並べ替えは同じフォルダの中だけ
        dragging?.folder == target.folder
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target, dragging.folder == target.folder else { return }
        onReorder(dragging, target)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

private struct FolderRowView: View {
    let name: String
    let depth: Int
    let hasChildren: Bool
    let isRoot: Bool
    let memoCount: Int
    let isSelected: Bool
    let isExpanded: Bool
    let helpText: String
    let onSelect: () -> Void
    let onToggleExpand: () -> Void
    let onNewMemo: () -> Void
    let onNewFolder: () -> Void
    let onReveal: () -> Void
    /// ルートは削除させない。
    let canDelete: Bool
    let onDelete: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            DisclosureChevron(
                isVisible: hasChildren && !isRoot,
                isExpanded: isExpanded,
                onToggle: onToggleExpand
            )
            Image(systemName: iconName)
                .font(.caption)
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 14)
            Text(name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if memoCount > 0 {
                Text("\(memoCount)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.leading, CGFloat(depth) * 12)
        .padding(.vertical, 3)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RowBackground(isSelected: isSelected, isCurrent: false, isHovering: isHovering))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .help(helpText)
        .contextMenu {
            Button("このフォルダに切り替え", action: onSelect)
            Divider()
            Button("新規メモ...", action: onNewMemo)
            Button("新規フォルダ...", action: onNewFolder)
            Divider()
            Button("Finder で開く", action: onReveal)
            if canDelete {
                Button("フォルダをゴミ箱へ", role: .destructive, action: onDelete)
            }
        }
    }

    private var iconName: String {
        if isRoot { return "house" }
        return isExpanded && hasChildren ? "folder.fill" : "folder"
    }
}

private struct MemoRowView: View {
    let fileName: String
    let depth: Int
    let isEnabled: Bool
    let isCurrent: Bool
    let isDragging: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onSelect: () -> Void
    let onToggleEnabled: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            DisclosureChevron(isVisible: false, isExpanded: false, onToggle: {})
            Image(systemName: iconName)
                .font(.caption)
                .foregroundColor(isCurrent ? .accentColor : .secondary)
                .frame(width: 14)
            Text(fileName)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if !isEnabled {
                // ローテーションから外れているメモは見て分かるようにしておく。
                Image(systemName: "moon.zzz")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .help("ローテーション対象外")
            }
        }
        .opacity(rowOpacity)
        .padding(.leading, CGFloat(depth) * 12)
        .padding(.vertical, 3)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RowBackground(isSelected: false, isCurrent: isCurrent, isHovering: isHovering))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .help(fileName)
        .contextMenu {
            Button("表示する", action: onSelect)
            Button(
                isEnabled ? "ローテーションから外す" : "ローテーションに含める",
                action: onToggleEnabled
            )
            Divider()
            Button("上へ移動", action: onMoveUp)
                .disabled(!canMoveUp)
            Button("下へ移動", action: onMoveDown)
                .disabled(!canMoveDown)
            Divider()
            Button("Finder で表示", action: onReveal)
            Button("ゴミ箱へ", role: .destructive, action: onDelete)
        }
    }

    private var rowOpacity: Double {
        if isDragging { return 0.35 }
        return isEnabled ? 1 : 0.55
    }

    private var iconName: String {
        if MemoEntry.isImage(id: fileName) { return "photo" }
        return URL(fileURLWithPath: fileName).pathExtension.lowercased() == "md"
            ? "doc.richtext"
            : "doc.plaintext"
    }
}

private struct DisclosureChevron: View {
    let isVisible: Bool
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        if isVisible {
            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.12), value: isExpanded)
        } else {
            Color.clear.frame(width: 12, height: 12)
        }
    }
}

private struct RowBackground: View {
    let isSelected: Bool
    let isCurrent: Bool
    let isHovering: Bool

    var body: some View {
        if isCurrent {
            Color.accentColor.opacity(0.25)
        } else if isSelected {
            Color.primary.opacity(0.12)
        } else if isHovering {
            Color.primary.opacity(0.07)
        } else {
            Color.clear
        }
    }
}

/// 新規メモ／新規フォルダで共用する名前入力シート。
private struct NameInputSheet: View {
    let title: String
    let caption: String?
    let locationLabel: String
    let placeholder: String
    @Binding var text: String
    let onCancel: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text("作成先: \(locationLabel)")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            HStack {
                Spacer()
                Button("キャンセル", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("作成", action: onCreate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
    }
}
