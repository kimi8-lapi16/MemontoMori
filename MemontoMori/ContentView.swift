import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var store: MemoStore
    @EnvironmentObject private var rotation: RotationController

    @State private var isPinned: Bool = false
    @State private var freeMemoText: String = ""
    @State private var showsSettingsPanel: Bool = false

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
        if store.entries.isEmpty {
            TextEditor(text: $freeMemoText)
                .padding()
                .background(Color(NSColor.textBackgroundColor))
                .font(.system(size: 14))
        } else if let id = rotation.currentID {
            FileMemoEditor(id: id)
                .id(id)
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
            pinButton
            rotationToggleButton

            Spacer()

            if !store.entries.isEmpty {
                Button {
                    rotation.advance(by: -1)
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
                    rotation.advance(by: 1)
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

            panelToggleButton
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

private struct FileMemoEditor: View {
    let id: String

    @EnvironmentObject private var store: MemoStore
    @EnvironmentObject private var rotation: RotationController

    @State private var text: String = ""
    @State private var didLoad: Bool = false
    @State private var skipNextChange: Bool = false

    var body: some View {
        TextEditor(text: $text)
            .padding()
            .background(Color(NSColor.textBackgroundColor))
            .font(.system(size: 14))
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
