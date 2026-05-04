import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: MemoStore
    @ObservedObject var rotation: RotationController

    @State private var showingNewMemoSheet: Bool = false
    @State private var newMemoName: String = ""
    @State private var errorMessage: String?
    @State private var pendingDeleteID: String?

    private static let intervalOptions: [(label: String, value: TimeInterval)] = [
        ("1分", 60), ("5分", 300), ("10分", 600), ("30分", 1800), ("60分", 3600)
    ]

    private static let idleOptions: [(label: String, value: TimeInterval)] = [
        ("1分", 60), ("3分", 180), ("5分", 300), ("10分", 600), ("30分", 1800)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("メモファイル")
                    .font(.headline)
                Spacer()
                Text(store.directoryURL.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            fileList
                .frame(minHeight: 180)

            HStack {
                Button {
                    newMemoName = ""
                    showingNewMemoSheet = true
                } label: {
                    Label("新規メモを作成", systemImage: "plus")
                }
                Button {
                    store.revealInFinder()
                } label: {
                    Label("Finderで開く", systemImage: "folder")
                }
                Button {
                    store.rescan()
                    rotation.reconcile()
                } label: {
                    Label("再スキャン", systemImage: "arrow.clockwise")
                }
                Spacer()
            }

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
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 460)
        .onAppear {
            store.rescan()
            rotation.reconcile()
        }
        .sheet(isPresented: $showingNewMemoSheet) {
            newMemoSheet
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

    @ViewBuilder
    private var fileList: some View {
        if store.entries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("メモがまだありません")
                    .foregroundColor(.secondary)
                Text("「新規メモを作成」または Finder からファイルを追加してください")
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
                        onToggle: { store.setEnabled(id: entry.id, enabled: $0) },
                        onDelete: { pendingDeleteID = entry.id }
                    )
                }
                .onMove { source, destination in
                    store.move(from: source, to: destination)
                    rotation.reconcile()
                }
            }
            .listStyle(.bordered)
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
        }
    }

    private var newMemoSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新規メモ")
                .font(.headline)
            Text("拡張子を省略すると .md として作成されます。")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("ファイル名", text: $newMemoName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            HStack {
                Spacer()
                Button("キャンセル") {
                    showingNewMemoSheet = false
                    newMemoName = ""
                }
                .keyboardShortcut(.cancelAction)
                Button("作成") {
                    createMemo()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newMemoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
    }

    private func createMemo() {
        let result = store.createMemo(name: newMemoName)
        switch result {
        case .success:
            showingNewMemoSheet = false
            newMemoName = ""
            rotation.reconcile()
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

private struct EntryRow: View {
    let entry: MemoEntry
    let modificationDate: Date?
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

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

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help("ゴミ箱に移動")
        }
        .padding(.vertical, 4)
    }
}
