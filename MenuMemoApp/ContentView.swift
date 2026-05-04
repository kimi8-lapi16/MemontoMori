import SwiftUI
import AppKit

struct ContentView: View {
    @State private var text: String = ""
    @State private var isPinned: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // テキストエリアがウィンドウ全体を使うように設定
            TextEditor(text: $text)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
                .font(.system(size: 14))

            // 下部にピン留めトグルと Clear ボタンを配置
            HStack {
                Button(action: { isPinned.toggle() }) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                }
                .help(isPinned ? "最前面表示を解除" : "常に最前面に表示")
                .buttonStyle(.borderless)
                .padding(.leading)

                Spacer()
                Button("Clear") {
                    text = ""
                }
                .padding()
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 300, minHeight: 200)
        .background(WindowAccessor(isPinned: $isPinned))
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
    ContentView()
}
