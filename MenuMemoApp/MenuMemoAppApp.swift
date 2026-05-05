//
//  MenuMemoAppApp.swift
//  MenuMemoApp
//
//  Created by 君島孝佳 on 2025/11/08.
//

import SwiftUI

@main
struct MenuMemoAppApp: App {
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

        Settings {
            SettingsView(store: store, rotation: rotation)
        }
        .windowResizability(.contentMinSize)
    }
}
