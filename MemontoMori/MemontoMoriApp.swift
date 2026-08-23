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
            // ⌘P はパレットに使うので、このアプリでは出番のない「プリント」を外す。
            CommandGroup(replacing: .printItem) {}
            CommandMenu("コマンド") {
                Button("ファイル・フォルダを検索...") {
                    store.togglePalette(.files)
                    activateMainWindow()
                }
                .keyboardShortcut("p", modifiers: .command)

                Button("コマンドを実行...") {
                    store.togglePalette(.commands)
                    activateMainWindow()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Divider()

                Button("新規メモ...") {
                    store.togglePalette(.newMemo)
                    activateMainWindow()
                }
                Button("新規フォルダ...") {
                    store.togglePalette(.newFolder)
                    activateMainWindow()
                }

                Divider()

                Button("前のメモへ") {
                    rotation.advance(by: -1, userInitiated: true)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(store.enabledEntries.count < 2)

                Button("次のメモへ") {
                    rotation.advance(by: 1, userInitiated: true)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(store.enabledEntries.count < 2)
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
