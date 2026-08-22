//
//  MemontoMoriApp.swift
//  MemontoMori
//
//  Created by 君島孝佳 on 2025/11/08.
//

import SwiftUI
import AppKit

@main
struct MemontoMoriApp: App {
    @StateObject private var store: MemoStore
    @StateObject private var rotation: RotationController

    init() {
        let store = MemoStore()
        _store = StateObject(wrappedValue: store)
        _rotation = StateObject(wrappedValue: RotationController(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(rotation)
        }
        .windowResizability(.contentMinSize)
        .commands {
            // 左ペインは作成・削除の入口も兼ねるので、閉じていても呼び出せるようにする。
            CommandGroup(after: .sidebar) {
                Button(store.folderSidebarVisible ? "フォルダツリーを隠す" : "フォルダツリーを表示") {
                    store.folderSidebarVisible.toggle()
                }
                .keyboardShortcut("1", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .appSettings) {
                Button("設定...") {
                    store.flushPending()
                    store.isShowingSettings = true
                    activateMainWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    private func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.isVisible }) ?? NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
