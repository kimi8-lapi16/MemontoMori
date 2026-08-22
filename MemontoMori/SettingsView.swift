import SwiftUI

/// ローテーションの並び順と動作設定を扱うパネル。
/// フォルダ移動・メモの作成／削除・Finder 表示は左ペイン（`FolderSidebar`）に集約したため、
/// ここは「巡回の順番」と「巡回のしかた」だけを担当する。
struct SettingsView: View {
    @ObservedObject var store: MemoStore
    @ObservedObject var rotation: RotationController

    /// 埋め込み表示時はウィンドウ最小サイズの強制を外したいので、外から指定できるようにする。
    var embedded: Bool = false

    private static let intervalOptions: [(label: String, value: TimeInterval)] = [
        ("1分", 60), ("5分", 300), ("10分", 600), ("30分", 1800), ("60分", 3600)
    ]

    private static let idleOptions: [(label: String, value: TimeInterval)] = [
        ("1分", 60), ("3分", 180), ("5分", 300), ("10分", 600), ("30分", 1800)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ローテーション順")
                    .font(.headline)
                Spacer()
                Text(currentLocationLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text("ドラッグで巡回する順番を入れ替えられます。チェックを外したメモは巡回対象から外れます。")
                .font(.caption)
                .foregroundColor(.secondary)

            fileList
                .frame(minHeight: 180)

            Divider()

            Text("動作設定")
                .font(.headline)

            Form {
                Picker("ローテーション間隔", selection: $store.rotationInterval) {
                    ForEach(Self.intervalOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                Picker("アイドル時間", selection: $store.idleTimeout) {
                    ForEach(Self.idleOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                Picker("画像切り替え", selection: $store.imageTransition) {
                    ForEach(ImageTransitionStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
            }
        }
        .padding()
        .frame(
            minWidth: embedded ? 320 : 520,
            maxWidth: .infinity,
            minHeight: embedded ? 0 : 460,
            maxHeight: .infinity
        )
        .onAppear {
            store.rescan()
            rotation.reconcile()
        }
    }

    private var currentLocationLabel: String {
        store.currentSubdirectory.isEmpty ? "（ルート）" : store.currentSubdirectory
    }

    @ViewBuilder
    private var fileList: some View {
        if store.entries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("メモがまだありません")
                    .foregroundColor(.secondary)
                Text("左のフォルダツリーの「新規メモ」から追加してください")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            List {
                ForEach(store.entries) { entry in
                    EntryRow(
                        entry: entry,
                        modificationDate: store.modificationDate(id: entry.id),
                        isCurrent: entry.id == rotation.currentID,
                        onToggle: { store.setEnabled(id: entry.id, enabled: $0) }
                    )
                }
                .onMove { source, destination in
                    store.move(from: source, to: destination)
                    rotation.reconcile()
                }
            }
            .listStyle(.bordered)
        }
    }
}

private struct EntryRow: View {
    let entry: MemoEntry
    let modificationDate: Date?
    let isCurrent: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle(
                "",
                isOn: Binding(
                    get: { entry.isEnabled },
                    set: onToggle
                )
            )
            .labelsHidden()
            .help(entry.isEnabled ? "ローテーションから外す" : "ローテーションに含める")

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(entry.id)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let date = modificationDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
