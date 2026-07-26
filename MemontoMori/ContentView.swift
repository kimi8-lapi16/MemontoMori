import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var store: MemoStore
    @EnvironmentObject private var rotation: RotationController

    @State private var isPinned: Bool = false
    @State private var freeMemoText: String = ""
    @State private var showsSettingsPanel: Bool = false
    @State private var isPreviewing: Bool = false

    /// 実際に画面へ出しているメモの ID。`rotation.currentID` の変更を
    /// `withAnimation` 経由で反映するために分離している（画像切り替えアニメーション用）。
    @State private var displayedID: String?

    private static let settingsPanelWidth: CGFloat = 380

    var body: some View {
        HStack(spacing: 0) {
            memoColumn
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)

            if showsSettingsPanel {
                Divider()
                SettingsView(store: store, rotation: rotation, embedded: true)
                    .frame(width: Self.settingsPanelWidth)
                    .background(Color(NSColor.windowBackgroundColor))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(
            minWidth: showsSettingsPanel ? 320 + Self.settingsPanelWidth : 320,
            minHeight: 260
        )
        .background(WindowAccessor(isPinned: $isPinned))
        .animation(.easeInOut(duration: 0.18), value: showsSettingsPanel)
        .onChange(of: rotation.currentID) { oldValue, newValue in
            updateDisplayedID(from: oldValue, to: newValue)
        }
    }

    /// 画像が絡む切り替えのときだけ、設定されたアニメーションを付けて表示を更新する。
    /// テキスト同士の切り替えは従来どおり即時。
    private func updateDisplayedID(from oldValue: String?, to newValue: String?) {
        let involvesImage = [oldValue, newValue]
            .compactMap { $0 }
            .contains { MemoEntry.isImage(id: $0) }
        if involvesImage, let animation = store.imageTransition.animation {
            withAnimation(animation) { displayedID = newValue }
        } else {
            displayedID = newValue
        }
    }

    private var memoColumn: some View {
        VStack(spacing: 0) {
            mainArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
                .background(Color(NSColor.windowBackgroundColor))
        }
    }

    @ViewBuilder
    private var mainArea: some View {
        // 切り替え途中は旧ビューと新ビューが同時に存在するため、
        // 縦に積まれてレイアウトが崩れないよう ZStack で重ねる。
        ZStack {
            mainAreaContent
        }
        // フェード中に新旧ビューが半透明になっても背後が透けないよう、下地を敷いておく。
        .background(Color(NSColor.textBackgroundColor))
        .clipped()
    }

    @ViewBuilder
    private var mainAreaContent: some View {
        if store.entries.isEmpty {
            PlainTextEditor(text: $freeMemoText)
                .background(Color(NSColor.textBackgroundColor))
        } else if let id = displayedID ?? rotation.currentID {
            if MemoEntry.isImage(id: id) {
                FileImageViewer(id: id)
                    .id(id)
                    .transition(store.imageTransition.transition)
            } else if isPreviewing && isMarkdownFile(id) {
                MarkdownPreview(id: id)
                    .id("preview:" + id)
            } else {
                FileMemoEditor(id: id)
                    .id(id)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("有効なメモがありません")
                    .foregroundColor(.secondary)
                Text("右のパネルから表示するメモを選択してください")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            // パネル開閉でウィンドウ幅が変わっても画面上の位置がずれないよう、
            // 左端（ウィンドウ原点側）に固定する。
            panelToggleButton
            pinButton
            rotationToggleButton
            previewToggleButton

            Spacer()

            if !store.entries.isEmpty {
                Button {
                    rotation.advance(by: -1, userInitiated: true)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .disabled(store.enabledEntries.count < 2)
                .help("前のメモへ")
            }

            if !store.entries.isEmpty, let id = rotation.currentID {
                Text(footerLabel(for: id))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 140)
            }

            if !store.entries.isEmpty {
                Button {
                    rotation.advance(by: 1, userInitiated: true)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(store.enabledEntries.count < 2)
                .help("次のメモへ")
            }

            Spacer()

            if store.entries.isEmpty {
                Button("Clear") { freeMemoText = "" }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
    }

    private var pinButton: some View {
        Button {
            isPinned.toggle()
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
        }
        .buttonStyle(.borderless)
        .help(isPinned ? "最前面表示を解除" : "常に最前面に表示")
    }

    private var rotationToggleButton: some View {
        Button {
            store.rotationEnabled.toggle()
        } label: {
            Image(
                systemName: store.rotationEnabled
                    ? "arrow.triangle.2.circlepath"
                    : "arrow.triangle.2.circlepath.circle"
            )
            .foregroundColor(store.rotationEnabled ? .accentColor : .secondary)
        }
        .buttonStyle(.borderless)
        .help(store.rotationEnabled ? "ローテーションをオフにする" : "ローテーションをオンにする")
    }

    @ViewBuilder
    private var previewToggleButton: some View {
        if let id = rotation.currentID, isMarkdownFile(id) {
            Button {
                if !isPreviewing {
                    store.flushPending()
                }
                isPreviewing.toggle()
            } label: {
                Image(systemName: isPreviewing ? "pencil" : "eye")
                    .foregroundColor(isPreviewing ? .accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help(isPreviewing ? "編集モードに戻る" : "Markdown プレビュー")
        }
    }

    private func isMarkdownFile(_ id: String) -> Bool {
        URL(fileURLWithPath: id).pathExtension.lowercased() == "md"
    }

    private var panelToggleButton: some View {
        Button {
            showsSettingsPanel.toggle()
        } label: {
            Image(systemName: showsSettingsPanel ? "sidebar.right" : "sidebar.squares.right")
        }
        .buttonStyle(.borderless)
        .help(showsSettingsPanel ? "設定パネルを閉じる" : "設定パネルを開く")
    }

    private func footerLabel(for id: String) -> String {
        let name = MemoEntry.displayName(for: id)
        let prefix: String
        if !store.rotationEnabled {
            prefix = "⏸"
        } else {
            prefix = rotation.mode == .rotating ? "🔄" : "✏️"
        }
        return "\(prefix) \(name)"
    }
}

private struct FileImageViewer: View {
    let id: String

    @EnvironmentObject private var store: MemoStore

    @State private var image: NSImage?
    @State private var didLoad: Bool = false

    var body: some View {
        Group {
            if let image {
                // 元サイズを上限にして縮小のみ。小さい画像は等倍で中央表示。
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: image.size.width, maxHeight: image.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if didLoad {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("画像を表示できません")
                        .foregroundColor(.secondary)
                    Text(id)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .onAppear { loadIfNeeded() }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        let url = store.directoryURL.appendingPathComponent(id)
        image = NSImage(contentsOf: url)
        didLoad = true
    }
}

private struct FileMemoEditor: View {
    let id: String

    @EnvironmentObject private var store: MemoStore
    @EnvironmentObject private var rotation: RotationController

    @State private var text: String = ""
    @State private var didLoad: Bool = false
    @State private var skipNextChange: Bool = false

    var body: some View {
        PlainTextEditor(text: $text)
            .background(Color(NSColor.textBackgroundColor))
            .onAppear { loadIfNeeded() }
            .onChange(of: text) { _, newValue in
                handleTextChange(newValue)
            }
            .onDisappear {
                store.flushPending()
            }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        let content = store.read(id: id)
        if content != text {
            skipNextChange = true
        }
        text = content
        didLoad = true
    }

    private func handleTextChange(_ newValue: String) {
        guard didLoad else { return }
        if skipNextChange {
            skipNextChange = false
            return
        }
        if rotation.mode == .rotating {
            rotation.enterEditingMode()
        }
        store.scheduleWrite(id: id, content: newValue)
    }
}

private struct MarkdownPreview: View {
    let id: String

    @EnvironmentObject private var store: MemoStore
    @State private var attributed: NSAttributedString = NSAttributedString()

    var body: some View {
        AttributedTextView(attributedString: attributed)
            .background(Color(NSColor.textBackgroundColor))
            .onAppear { attributed = MarkdownRenderer.render(store.read(id: id)) }
    }
}

private struct AttributedTextView: NSViewRepresentable {
    let attributedString: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]
        textView.textStorage?.setAttributedString(attributedString)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(attributedString)
    }
}

private struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true

        // スマートクオート (curly quote) や ハイフン→ダッシュ などの自動置換を無効化する。
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.string = text
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

private struct WindowAccessor: NSViewRepresentable {
    @Binding var isPinned: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            apply(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView.window)
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        window.level = isPinned ? .floating : .normal
    }
}

#Preview {
    let store = MemoStore()
    ContentView()
        .environmentObject(store)
        .environmentObject(RotationController(store: store))
}
