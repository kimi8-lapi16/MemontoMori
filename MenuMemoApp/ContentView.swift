import SwiftUI

struct ContentView: View {
    @State private var text: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // テキストエリアがウィンドウ全体を使うように設定
            TextEditor(text: $text)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
                .font(.system(size: 14))

            // 下部に Clear ボタンを配置
            HStack {
                Spacer()
                Button("Clear") {
                    text = ""
                }
                .padding()
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 300, minHeight: 200)
    }
}

#Preview {
    ContentView()
}
