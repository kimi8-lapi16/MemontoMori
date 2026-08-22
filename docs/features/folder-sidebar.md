---
id: folder-sidebar
title: フォルダツリー（左ペイン）
sidebar_label: フォルダツリー
sidebar_position: 7
description: IDE のファイルツリーのように、フォルダ階層を左ペインに常時表示してワンクリックで切り替える機能。
---

# フォルダツリー（左ペイン）

サブフォルダが増えてくると、設定パネルのプルダウンから目的のフォルダを選び直すのが面倒になります。そこで、IDE やエディタのファイルツリーと同じように **フォルダ階層を左ペインに出しっぱなし** にして、行をクリックした瞬間に切り替わるようにしました。

## 使い方

| 操作 | 動作 |
| --- | --- |
| フッター左端の `sidebar.left` ボタン | 左ペインの開閉（状態は次回起動にも引き継がれる） |
| フォルダ行をクリック | そのフォルダへ即切り替え（`（ルート）` は `MemontoMori` の行） |
| 選択中の行をもう一度クリック | 折りたたみ／展開のトグル |
| 左の `>` （三角） | 子フォルダの折りたたみ／展開 |
| 行を右クリック | 「このフォルダに切り替え」「Finder で開く」 |
| ヘッダーの `再スキャン` | Finder 側で作ったフォルダを取り込む |
| 左ペインと本文の境目をドラッグ | 幅を変更（140〜400pt、幅も保存される） |

```
🏠 MemontoMori        ← （ルート）
  ▾ 📁 work
      📁 standup
    📁 private
```

フォルダを切り替えると、そのフォルダの並び順・有効状態・最後に見ていたメモがそのまま復元されます（詳細は[サブフォルダの切り替え](./subdirectories.md)）。

## 仕組み

### フラットな相対パスを木に組み直す

`MemoStore.availableSubdirectories` はルートからの相対パスを平坦に並べた配列です。左ペインで描くには木構造が必要なので、`FolderNode.build(rootName:relativePaths:)` が親子関係を復元します。途中のフォルダが列挙から漏れていても木が途切れないよう、祖先パスを補完してから組み立てます。

```swift title="FolderTree.swift（抜粋）"
struct FolderNode: Identifiable, Equatable {
    /// ルートからの相対パス。ルート自身は空文字。
    let id: String
    let name: String
    let children: [FolderNode]

    static func build(rootName: String, relativePaths: [String]) -> FolderNode
}
```

### 描画するのは「展開されている行」だけ

`visibleRows(isExpanded:)` が展開状態にしたがって木を上から平坦化し、`LazyVStack` はその配列をそのまま並べます。インデントは行の `depth` から計算するので、階層が深くなってもビューのネストは増えません。

```swift title="FolderTree.swift（抜粋）"
func visibleRows(isExpanded: (String) -> Bool) -> [FolderRow]
```

### 展開状態と選択の同期

展開状態は `MemoStore.expandedFolders`（相対パスの `Set`）として `UserDefaults` に保存されます。フォルダを選ぶと `expandAncestors(of:)` が祖先をまとめて開くので、**折りたたまれた枝の中に選択中フォルダが隠れる**ことがありません。起動直後や、設定パネルのプルダウンから切り替えたときも同じ経路を通ります。

```swift title="MemoStore.swift（抜粋）"
func expandAncestors(of relativePath: String) {
    guard !relativePath.isEmpty else { return }
    var accumulated: [String] = []
    var opened = expandedFolders
    for component in relativePath.split(separator: "/") {
        accumulated.append(String(component))
        opened.insert(accumulated.joined(separator: "/"))
    }
    if opened != expandedFolders { expandedFolders = opened }
}
```

Finder でフォルダを消した場合は、`refreshAvailableSubdirectories()` が実在しないパスの展開状態を取り除きます。

### フッターを最下段いっぱいに移した理由

左ペインはメモ本文の左に入るため、フッターをメモ列の中に置いたままだと、開閉のたびにトグルボタンが左右にずれてしまいます。そこでレイアウトを「横並び（左ペイン／本文／設定パネル）＋その下にフッター」に変更し、ボタン位置をウィンドウ左下に固定しました。

```swift title="ContentView.swift（抜粋）"
VStack(spacing: 0) {
    HStack(spacing: 0) {
        if store.folderSidebarVisible {
            FolderSidebar(store: store, rotation: rotation)
                .frame(width: CGFloat(store.folderSidebarWidth))
                .transition(.move(edge: .leading).combined(with: .opacity))
            sidebarResizeHandle
        }
        mainArea.frame(minWidth: 320, maxWidth: .infinity)
        if showsSettingsPanel { Divider(); SettingsView(..., embedded: true) }
    }
    Divider()
    footer
}
```

ウィンドウ最小幅は `本文 320 + (左ペイン幅 + 1) + (設定パネル 380)` として、開いているペインぶんだけ動的に広がります。

:::tip 設定パネルのプルダウンは残しています
左ペインを閉じていても従来どおりフォルダを選べるよう、[分割パネル設定](./split-panel-settings.md)側のフォルダピッカーはそのままです。新規フォルダの作成も設定パネル側から行えます。
:::
