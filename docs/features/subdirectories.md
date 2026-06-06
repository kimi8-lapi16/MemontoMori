---
id: subdirectories
title: サブフォルダの切り替え
sidebar_label: サブフォルダ
sidebar_position: 3
description: ローテーション対象のディレクトリをサブフォルダ単位で選択する機能。
---

# サブフォルダの切り替え

メモを増やしすぎると、全部まとめて巡回されても困ります。MemontoMori は `Documents/MemontoMori/` 配下の **サブフォルダ単位** で、表示・ローテーション対象を切り替えられます。

> 由来: PR #4「ローテーション対象のサブディレクトリを選択可能にする」

## 使い方

設定パネル上部のフォルダピッカーで対象を選びます。

- `（ルート）` … `Documents/MemontoMori/` 直下のメモ。
- それ以外 … 選んだサブフォルダ内のメモ。

ネストしたフォルダはインデント付きで一覧表示されます。

```
（ルート）
  work
    standup
  private
```

`新規フォルダを作成` ボタンで、現在のフォルダ内に子フォルダを作って即移動できます。

## 仕組み

### スキャンと相対パス管理

`MemoStore` はルート直下を再帰列挙し、ディレクトリの **相対パス** を `availableSubdirectories` として保持します。

```swift title="MemoStore.swift（抜粋）"
var directoryURL: URL {
    currentSubdirectory.isEmpty
        ? rootDirectoryURL
        : rootDirectoryURL.appendingPathComponent(currentSubdirectory, isDirectory: true)
}
```

メモの読み書き・作成・削除はすべて、この `directoryURL`（= 現在選択中のフォルダ）に対して行われます。

### フォルダ単位で状態を分離

並び順・有効状態・最後に見たメモは、フォルダごとに別キーで `UserDefaults` に保存されます。

```swift title="MemoStore.swift（抜粋）"
private static func entriesKey(for subdir: String) -> String {
    subdir.isEmpty ? "memontoMori.entries" : "memontoMori.entries.\(subdir)"
}
private static func lastIDKey(for subdir: String) -> String {
    subdir.isEmpty ? "memontoMori.lastDisplayedID" : "memontoMori.lastDisplayedID.\(subdir)"
}
```

これにより、フォルダを切り替えても「そのフォルダでの並び順・続きの位置」がそれぞれ独立して保たれます。

### Finder 削除へのフォールバック

選択中のフォルダが Finder などで消された場合、`rescan()` がそれを検知し、自動的に `（ルート）` にフォールバックします。

```swift title="MemoStore.swift（抜粋）"
if !currentSubdirectory.isEmpty && !availableSubdirectories.contains(currentSubdirectory) {
    currentSubdirectory = ""
    lastDisplayedID = UserDefaults.standard.string(forKey: Self.lastIDKey(for: ""))
}
```

:::caution フォルダ名の制約
`createSubdirectory(name:)` は `/`・`\`・`.` 始まり・`.`／`..` を拒否します。OS のパス区切りや隠しフォルダ化を避けるためのバリデーションです。
:::
</content>
