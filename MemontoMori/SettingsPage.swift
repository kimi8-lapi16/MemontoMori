import SwiftUI

/// 本文エリアを丸ごと差し替えて表示する設定ページ。
///
/// 以前は右側の分割パネルに置いていたが、ここにある項目はどれもフォルダ単位ではなく
/// アプリ全体に効く設定なので、VS Code と同じく「設定ページに切り替える」形にした。
/// フォルダやメモの操作・並べ替えは左ペイン（`FolderSidebar`）が担当する。
struct SettingsPage: View {
    @ObservedObject var store: MemoStore

    private static let intervalOptions: [(label: String, value: TimeInterval)] = [
        ("1分", 60), ("5分", 300), ("10分", 600), ("30分", 1800), ("60分", 3600)
    ]

    private static let idleOptions: [(label: String, value: TimeInterval)] = [
        ("1分", 60), ("3分", 180), ("5分", 300), ("10分", 600), ("30分", 1800)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                section("ローテーション") {
                    settingRow(
                        title: "自動ローテーション",
                        description: "オフにすると、操作していなくてもメモが切り替わらなくなります。"
                    ) {
                        Toggle("", isOn: $store.rotationEnabled)
                            .labelsHidden()
                    }

                    settingRow(
                        title: "ローテーション間隔",
                        description: "巡回中に次のメモへ切り替わるまでの時間です。"
                    ) {
                        Picker("", selection: $store.rotationInterval) {
                            ForEach(Self.intervalOptions, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                    .disabled(!store.rotationEnabled)

                    settingRow(
                        title: "アイドル時間",
                        description: "この時間だけ操作がないと、編集モードから巡回モードに移ります。"
                    ) {
                        Picker("", selection: $store.idleTimeout) {
                            ForEach(Self.idleOptions, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                    .disabled(!store.rotationEnabled)
                }

                section("表示") {
                    settingRow(
                        title: "画像の切り替えアニメーション",
                        description: "画像メモが切り替わるときの見せ方を選べます。"
                    ) {
                        Picker("", selection: $store.imageTransition) {
                            ForEach(ImageTransitionStyle.allCases) { style in
                                Text(style.label).tag(style)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }

                    settingRow(
                        title: "フォルダツリー",
                        description: "左ペインの表示・非表示を切り替えます（⌥⌘1）。"
                    ) {
                        Toggle("", isOn: $store.folderSidebarVisible)
                            .labelsHidden()
                    }
                }

                section("コマンド") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("⌘P でファイル・フォルダの絞り込み検索、⇧⌘P でコマンドの絞り込み実行を開きます。")
                            .font(.system(size: 13, weight: .medium))
                        Text("検索欄の先頭が > のときはコマンド、そうでないときはファイル・フォルダの検索になります。"
                            + "入力した文字が順番どおり含まれていれば拾う fzf 方式なので、"
                            + "wsd と打つだけで work/standup/daily.md まで辿り着けます。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    keyHintTable

                    ForEach(CommandCategory.allCases) { category in
                        commandGroup(category)
                    }
                }

                section("保存場所") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.rootDirectoryURL.path)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Text("メモはこのフォルダ配下に、ただのテキスト／画像ファイルとして置かれます。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button {
                            store.revealInFinder(relativePath: "")
                        } label: {
                            Label("Finder で開く", systemImage: "folder")
                        }
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(28)
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    /// パレットを開いている間だけ効くキー操作。コマンド一覧とは別枠で見せる。
    private var keyHintTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("パレットのキー操作")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            ForEach(CommandCatalog.keyHints) { hint in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(hint.keys)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 130, alignment: .leading)
                    Text(hint.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func commandGroup(_ category: CommandCategory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            ForEach(CommandCatalog.commands(in: category)) { descriptor in
                commandRow(descriptor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commandRow(_ descriptor: CommandDescriptor) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: descriptor.systemImage)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.title)
                    .font(.system(size: 13, weight: .medium))
                Text(descriptor.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if let shortcut = descriptor.shortcut {
                Text(shortcut)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.07))
                    )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("設定")
                .font(.title2.weight(.semibold))
            Text("ここでの設定はすべてのフォルダに共通で適用されます。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Divider()
            content()
        }
    }

    private func settingRow<Control: View>(
        title: String,
        description: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            control()
        }
    }
}
