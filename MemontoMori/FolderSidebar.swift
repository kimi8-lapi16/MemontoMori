import SwiftUI
import AppKit

/// エディタや IDE のファイルツリーのように、フォルダ階層を左ペインに出す。
/// 行をクリックするとその場でローテーション対象フォルダが切り替わる。
struct FolderSidebar: View {
    @ObservedObject var store: MemoStore
    @ObservedObject var rotation: RotationController

    private var tree: FolderNode {
        FolderNode.build(
            rootName: MemoStore.directoryName,
            relativePaths: store.availableSubdirectories
        )
    }

    private var rows: [FolderRow] {
        tree.visibleRows { store.isExpanded($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(rows) { row in
                        FolderRowView(
                            row: row,
                            isSelected: row.id == store.currentSubdirectory,
                            isExpanded: store.isExpanded(row.id),
                            onSelect: { select(row.id) },
                            onToggleExpand: { store.toggleExpansion(row.id) },
                            onReveal: { store.revealInFinder(relativePath: row.id) }
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear { store.refreshAvailableSubdirectories() }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("フォルダ")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
            Button {
                store.rescan()
                rotation.reconcile()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("フォルダを再スキャン")
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
    }

    private func select(_ relativePath: String) {
        if relativePath == store.currentSubdirectory {
            // 選択済みの行を押したときは開閉のトグルとして扱う（IDE と同じ感覚）
            store.toggleExpansion(relativePath)
            return
        }
        store.selectSubdirectory(relativePath)
        rotation.reconcile()
    }
}

private struct FolderRowView: View {
    let row: FolderRow
    let isSelected: Bool
    let isExpanded: Bool
    let onSelect: () -> Void
    let onToggleExpand: () -> Void
    let onReveal: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            disclosure
            Image(systemName: iconName)
                .font(.caption)
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 14)
            Text(row.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(.primary)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * 12)
        .padding(.vertical, 3)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .help(row.isRoot ? "（ルート）" : row.id)
        .contextMenu {
            Button("このフォルダに切り替え", action: onSelect)
            Button("Finder で開く", action: onReveal)
        }
    }

    @ViewBuilder
    private var disclosure: some View {
        // ルートは常に開いた状態なので、押しても何も起きない三角は出さない。
        if row.hasChildren && !row.isRoot {
            Button(action: onToggleExpand) {
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

    private var iconName: String {
        if row.isRoot { return "house" }
        return isExpanded && row.hasChildren ? "folder.fill" : "folder"
    }

    @ViewBuilder
    private var background: some View {
        if isSelected {
            Color.accentColor.opacity(0.22)
        } else if isHovering {
            Color.primary.opacity(0.07)
        } else {
            Color.clear
        }
    }
}
