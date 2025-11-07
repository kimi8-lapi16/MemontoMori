import SwiftUI

struct ContentView: View {
    @AppStorage("memoText") private var memoText: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Memo")
                .font(.headline)
            
            TextEditor(text: $memoText)
                .frame(width: 250, height: 150)
                .border(Color.gray.opacity(0.3))
            
            HStack {
                Spacer()
                Button("Clear") {
                    memoText = ""
                }
                .keyboardShortcut("c", modifiers: .command)
            }
        }
        .padding(12)
    }
}
