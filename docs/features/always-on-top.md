---
id: always-on-top
title: 常に最前面に表示（ピン留め）
sidebar_label: 常に最前面
sidebar_position: 1
description: ウィンドウを floating レベルに固定して最前面表示するピン機能。
---

# 常に最前面に表示（ピン留め）

フッター左端の 📌 ボタンで、メモウィンドウを他のアプリより前面に固定できます。
コードを写経しながらメモを見たい、会議中にチェックリストを出しっぱなしにしたい、といった用途向けです。

> 由来: PR #1「add always-on-top pin toggle to memo window」

## 使い方

| 操作 | 結果 |
| --- | --- |
| フッターの `pin`（外枠のみ）をクリック | 最前面に固定（`pin.fill` に変化） |
| もう一度クリック | 通常の重なり順に戻す |

ツールチップは状態に応じて「常に最前面に表示」/「最前面表示を解除」と切り替わります。

## 仕組み

ピンの実体は `NSWindow.level` の切り替えです。SwiftUI のウィンドウに直接アクセスできないため、`NSViewRepresentable`（`WindowAccessor`）で `view.window` を取り出して `level` を設定します。

```swift title="ContentView.swift（抜粋）"
private struct WindowAccessor: NSViewRepresentable {
    @Binding var isPinned: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view.window) }
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
```

- `isPinned` は `ContentView` の `@State`。トグルすると `updateNSView` 経由で `window.level` が更新されます。
- 生成直後は `window` がまだ `nil` のことがあるため、`makeNSView` 内では `DispatchQueue.main.async` で遅延適用しています。

:::caution Popover との関係
このアプリは `NSPopover`（メニューバー）と `WindowGroup` の両方の入口を持ちます。ピン留めが効くのはウィンドウとして開いた場合です。`.floating` は通常ウィンドウより前面ですが、他アプリのフルスクリーン表示などには勝てない点に注意してください。
:::
