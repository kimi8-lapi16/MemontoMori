---
id: folder-sidebar
title: フォルダツリー（左ペイン）
sidebar_label: フォルダツリー
sidebar_position: 7
description: IDE のファイルツリーのように、フォルダ階層とメモを左ペインに表示し、切り替え・作成・削除までまとめて行う機能。
---

# フォルダツリー（左ペイン）

サブフォルダが増えてくると、設定パネルのプルダウンから目的のフォルダを選び直すのが面倒になります。そこで、IDE やエディタのファイルツリーと同じように **フォルダ階層とメモを左ペインに出しっぱなし** にして、行をクリックした瞬間に切り替わるようにしました。

あわせて、それまで設定パネルに同居していた **ファイル操作（作成・削除・Finder 表示・再スキャン）を左ペインへ集約** しています。設定パネルは「巡回の順番と巡回のしかた」だけを担当します。

| | 担当 |
| --- | --- |
| 左ペイン（フォルダツリー） | フォルダ移動、メモの選択、メモ／フォルダの作成、削除、Finder 表示、再スキャン |
| 右ペイン（[設定パネル](./split-panel-settings.md)） | ローテーション順の並べ替え、巡回対象のオン/オフ、間隔・アイドル時間・画像切り替え |

## 使い方

### 開閉

| 操作 | 動作 |
| --- | --- |
| フッター左端の `sidebar.left` ボタン | 左ペインの開閉 |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>1</kbd>（表示メニュー） | 同上。左ペインは作成の入口も兼ねるので、閉じていても呼び戻せるようにしてある |
| 左ペインと本文の境目をドラッグ | 幅を変更（140〜400pt） |

表示状態・幅・どのフォルダを開いていたかは `UserDefaults` に保存され、次回起動時に復元されます。

### ツリーの操作

```
🏠 MemontoMori        3   ← （ルート）。右端の数字はそのフォルダのメモ数
  ▾ 📁 work           2
      📁 standup      5
        📄 daily.md       ← ローテーション対象フォルダのメモだけが並ぶ
        📄 review.md
        🌙 old.md         ← ローテーション対象外
    📁 private        1
```

| 操作 | 動作 |
| --- | --- |
| フォルダ行をクリック | そのフォルダへ即切り替え（`（ルート）` は `MemontoMori` の行） |
| 選択中のフォルダ行をクリック | 折りたたみ／展開のトグル |
| 三角（`>`） | 子フォルダ・メモの折りたたみ／展開 |
| メモ行をクリック | 表示するメモを即切り替え |
| ヘッダーの 4 ボタン | 新規メモ / 新規フォルダ / Finder で開く / 再スキャン |
| フォルダ行を右クリック | このフォルダに切り替え、新規メモ、新規フォルダ、Finder で開く |
| メモ行を右クリック | 表示する、ローテーションに含める・外す、Finder で表示、ゴミ箱へ |

メモ行が並ぶのは **ローテーション対象フォルダ（選択中のフォルダ）だけ** です。並び順・有効状態はフォルダごとに独立して保存されているため（[サブフォルダの切り替え](./subdirectories.md)）、「いま巡回しているフォルダ」がひと目で分かる形にしています。他のフォルダは行の右端にメモ数だけを出し、クリックして切り替えると中身が展開されます。

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

`rows(isExpanded:memoCount:memos:)` が展開状態にしたがって木を平坦化し、フォルダ行とメモ行が混ざった `[SidebarRow]` を返します。`LazyVStack` はその配列をそのまま並べるだけなので、階層が深くなってもビューのネストは増えません。インデントは行が持つ `depth` から計算します。

```swift title="FolderTree.swift（抜粋）"
struct SidebarRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case folder(hasChildren: Bool, isRoot: Bool, memoCount: Int)
        case memo(isEnabled: Bool)
    }
    let id: String          // "dir:work/standup" / "memo:work/daily.md"
    let folderPath: String
    let name: String
    let depth: Int
    let kind: Kind
}
```

メモ行を供給するのはビュー側のクロージャなので、「対象フォルダだけメモを出す」という方針はモデルではなく `FolderSidebar` 側に閉じています。

```swift title="FolderSidebar.swift（抜粋）"
.rows(
    isExpanded: { store.isExpanded($0) },
    memoCount: { store.memoCount(in: $0) },
    // メモを持てるのはローテーション対象フォルダだけなので、そこにだけ並べる。
    memos: { $0 == store.currentSubdirectory ? store.entries : [] }
)
```

### メモ数は走査 1 回で数える

フォルダ行の右端に出すメモ数のために毎回ディスクを見に行くと描画のたびに走査が走ってしまうため、フォルダ列挙と同じ 1 パスで数えて `memoCounts` に持たせています。

```swift title="MemoStore.swift（抜粋）"
private static func scanFolders(root: URL) -> (paths: [String], counts: [String: Int]) {
    ...
    if isDir {
        paths.append(rel)
    } else if supportedExtensions.contains(url.pathExtension.lowercased()) {
        let parent = rel.split(separator: "/").dropLast().joined(separator: "/")
        counts[parent, default: 0] += 1
    }
}
```

### 展開状態と選択の同期

展開状態は `MemoStore.expandedFolders`（相対パスの `Set`）として `UserDefaults` に保存されます。フォルダを選ぶと `expandAncestors(of:)` が祖先をまとめて開くので、**折りたたまれた枝の中に選択中フォルダが隠れる**ことがありません。起動直後も同じ経路を通ります。

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

### 作成は「現在のフォルダ」に対して行う

`MemoStore.createMemo(name:)` / `createSubdirectory(name:)` はどちらも `directoryURL`（= 選択中のフォルダ）に作ります。そのため、別フォルダの行から作成を呼んだときは **先にそのフォルダへ切り替えてからシートを出す** 形にしました。ストア側に「作成先フォルダ」を引数で持ち込まずに済み、作成後の表示先とも食い違いません。

```swift title="FolderSidebar.swift（抜粋）"
private func beginCreateMemo(in relativePath: String) {
    selectFolderIfNeeded(relativePath)
    newMemoName = ""
    showingNewMemoSheet = true
}
```

新規メモの作成が成功すると、そのままそのメモへ表示を移します（`rotation.switchTo(id:)`）。

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

:::caution 並べ替えは設定パネル側に残しています
ローテーション順のドラッグ並べ替えはリスト表示のほうが扱いやすいため、[設定パネル](./split-panel-settings.md)に残しました。左ペインは「どれを見るか」、設定パネルは「どの順で巡回するか」という分担です。
:::
