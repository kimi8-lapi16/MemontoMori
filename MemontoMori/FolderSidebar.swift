import SwiftUI
import AppKit

/// エディタや IDE のファイルツリーのように、フォルダ階層とメモを左ペインに出す。
/// フォルダ行のクリックでローテーション対象フォルダを、メモ行のクリックで表示中のメモを
/// その場で切り替える。作成・削除・Finder 表示もこのペインに集約している。
struct FolderSidebar: View {
    @ObservedObject var store: MemoStore
    @ObservedObject var rotation: RotationController

    @State private var showingNewMemoSheet: Bool = false
    @State private var newMemoName: String = ""
    @State private var showingNewFolderSheet: Bool = false
    @State private var newFolderName: String = ""
    @State private var errorMessage: String?
    @State private var pendingDeleteID: String?

    private var rows: [SidebarRow] {
        FolderNode
            .build(
                rootName: MemoStore.directoryName,
                relativePaths: store.availableSubdirectories
            )
            .rows(
                isExpanded: { store.isExpanded($0) },
                memoCount: { store.memoCount(in: $0) },
                // メモを持てるのはローテーション対象フォルダだけなので、そこにだけ並べる。
                memos: { $0 == store.currentSubdirectory ? store.entries : [] }
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
        .onAppear { store.refreshAvailableSubdirectories() }
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
                get: { pendingDeleteID != nil },
                set: { if !$0 { pendingDeleteID = nil } }
            ),
            presenting: pendingDeleteID
        ) { id in
            Button("ゴミ箱へ", role: .destructive) {
                store.deleteMemo(id: id)
                rotation.reconcile()
                pendingDeleteID = nil
            }
            Button("キャンセル", role: .cancel) { pendingDeleteID = nil }
        } message: { id in
            Text("「\(MemoEntry.displayName(for: id))」をゴミ箱に移動します。")
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
                onReveal: { store.revealInFinder(relativePath: row.folderPath) }
            )
        case let .memo(isEnabled):
            MemoRowView(
                fileName: row.name,
                depth: row.depth,
                isEnabled: isEnabled,
                isCurrent: row.name == rotation.currentID,
                onSelect: { rotation.switchTo(id: row.name) },
                onToggleEnabled: {
                    store.setEnabled(id: row.name, enabled: !isEnabled)
                    rotation.reconcile()
                },
                onReveal: { store.revealInFinder(memoID: row.name) },
                onDelete: { pendingDeleteID = row.name }
            )
        }
    }

    private var currentLocationLabel: String {
        store.currentSubdirectory.isEmpty ? "（ルート）" : store.currentSubdirectory
    }

    private func selectFolder(_ relativePath: String) {
        if relativePath == store.currentSubdirectory {
            // 選択済みの行を押したときは開閉のトグルとして扱う（IDE と同じ感覚）
            store.toggleExpansion(relativePath)
            return
        }
        store.selectSubdirectory(relativePath)
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
    let onSelect: () -> Void
    let onToggleEnabled: () -> Void
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
        .opacity(isEnabled ? 1 : 0.55)
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
            Button("Finder で表示", action: onReveal)
            Button("ゴミ箱へ", role: .destructive, action: onDelete)
        }
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
