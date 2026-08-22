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
