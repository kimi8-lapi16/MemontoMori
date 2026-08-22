---
id: folder-sidebar
title: フォルダツリー（左ペイン）
sidebar_label: フォルダツリー
sidebar_position: 7
description: IDE のファイルツリーのように、フォルダ階層とメモを左ペインに表示し、切り替え・作成・削除までまとめて行う機能。
---

# フォルダツリー（左ペイン）

サブフォルダが増えてくると、プルダウンから目的のフォルダを選び直すのが面倒になります。そこで、IDE やエディタのファイルツリーと同じように **フォルダ階層とメモを左ペインに出しっぱなし** にして、行をクリックした瞬間に切り替わるようにしました。

**メモに関する操作はすべてこのペインに集約**しています。かつて右側の分割パネルにあったファイル一覧・フォルダ選択・作成・並べ替えはここへ移り、アプリ全体に効く設定だけが[設定ページ](./settings-page.md)に残りました。

| | 担当 |
| --- | --- |
| 左ペイン（フォルダツリー） | フォルダ移動、メモの選択、作成、並べ替え、巡回対象のオン/オフ、削除、Finder 表示、再スキャン |
| [設定ページ](./settings-page.md) | ローテーション間隔・アイドル時間・画像切り替えなど、フォルダによらない全体設定 |

## 使い方

### 開閉

| 操作 | 動作 |
| --- | --- |
| フッター左端の `sidebar.left` ボタン | 左ペインの開閉 |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>1</kbd>（表示メニュー） | 同上。左ペインは作成の入口も兼ねるので、閉じていても呼び戻せるようにしてある。[設定ページ](./settings-page.md)からも切り替えられる |
| 左ペインと本文の境目をドラッグ | 幅を変更（140〜400pt） |

表示状態・幅・どのフォルダを開いていたかは `UserDefaults` に保存され、次回起動時に復元されます。

### ツリーの操作

```
🏠 MemontoMori        3   ← （ルート）。右端の数字はそのフォルダのメモ数
  ▾ 📁 work           2
    ▸ 📁 standup      5   ← 開けばどのフォルダの中身も見られる
      📄 daily.md
      📄 review.md
      🌙 old.md           ← ローテーション対象外
    📁 private        1
```

| 操作 | 動作 |
| --- | --- |
| フォルダ行をクリック | そのフォルダへ即切り替え（`（ルート）` は `MemontoMori` の行） |
| 選択中のフォルダ行をクリック | 折りたたみ／展開のトグル |
| 三角（`>`） | 子フォルダ・メモの折りたたみ／展開 |
| メモ行をクリック | 表示するメモを即切り替え（別フォルダのメモなら、そのフォルダへ切り替えてから表示） |
| メモ行をドラッグ | 同じフォルダ内でローテーション順を並べ替え |
| ヘッダーの 4 ボタン | 新規メモ / 新規フォルダ / Finder で開く / 再スキャン |
| フォルダ行を右クリック | このフォルダに切り替え、新規メモ、新規フォルダ、Finder で開く、フォルダをゴミ箱へ |
| メモ行を右クリック | 表示する、ローテーションに含める・外す、上へ／下へ移動、Finder で表示、ゴミ箱へ |

**どのフォルダも開閉できます。** 開けばその中のメモが並ぶので、切り替えなくても中身を確認できます。行の右端の数字は、そのフォルダが持つメモの件数です。

ローテーションの対象になるのは選択中フォルダのメモだけですが、並び順と有効/無効は[フォルダごとに独立して保存](./subdirectories.md)されるため、他フォルダのメモも開いたまま並べ替え・オン/オフの変更ができます。

:::caution フォルダの削除は中身ごと
フォルダ行の「フォルダをゴミ箱へ」は、中のメモとサブフォルダをまとめてゴミ箱へ移します（確認ダイアログあり）。ルート行にはこの項目は出ません。削除したフォルダを選択中だった場合は、`rescan()` がルートへフォールバックします。
:::

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

メモ行を供給するのはビュー側のクロージャです。

```swift title="FolderSidebar.swift（抜粋）"
.rows(
    isExpanded: { store.isExpanded($0) },
    memoCount: { store.memoCount(in: $0) },
    memos: { store.memos(in: $0) }
)
```

### フォルダごとのメモ一覧を持つ

どのフォルダも開けるようにするには、選択中フォルダ以外のメモ一覧も要ります。描画のたびにディスクを見に行かずに済むよう、**フォルダ走査と同じ 1 パスでファイル名も集め**、保存済みの並び順・有効状態と突き合わせた結果を `folderEntries` に保持します。

```swift title="MemoStore.swift（抜粋）"
/// フォルダごとのメモ一覧。キーはルートからの相対パス（ルートは空文字）。
@Published private(set) var folderEntries: [String: [MemoEntry]] = [:]

/// 保存済みの並び順・有効状態と、実在するファイルを突き合わせる。
private static func merge(stored: [MemoEntry], presentNames: Set<String>) -> [MemoEntry] {
    var ordered = stored.filter { presentNames.contains($0.id) }
    let knownIDs = Set(ordered.map(\.id))
    for name in presentNames.subtracting(knownIDs).sorted() {
        ordered.append(MemoEntry(id: name, isEnabled: true))
    }
    return ordered
}
```

`entries`（選択中フォルダの一覧＝ローテーション対象）は従来どおり残し、更新は `apply(_:for:)` 1 か所を通して `folderEntries`・`entries`・`UserDefaults` の 3 つを同時に書き換えます。どのフォルダのメモを操作しても状態がずれません。

### 並べ替えはドラッグと右クリックの二本立て

行の上に別の行がドラッグされてきた時点で入れ替える、よくある方式です。並べ替えは**同じフォルダの中だけ**に限定しています。

```swift title="FolderSidebar.swift（抜粋）"
private struct MemoReorderDropDelegate: DropDelegate {
    let target: MemoRef
    @Binding var dragging: MemoRef?
    let onReorder: (MemoRef, MemoRef) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        // 並べ替えは同じフォルダの中だけ
        dragging?.folder == target.folder
    }
    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target, dragging.folder == target.folder else { return }
        onReorder(dragging, target)
    }
}
```

細かい調整をしたいときのために、右クリックメニューの「上へ移動 / 下へ移動」でも 1 つずつ動かせます。

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

左ペインはメモ本文の左に入るため、フッターをメモ列の中に置いたままだと、開閉のたびにトグルボタンが左右にずれてしまいます。そこでレイアウトを「横並び（左ペイン／本文）＋その下にフッター」に変更し、ボタン位置をウィンドウ左下に固定しました。

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
    }
    Divider()
    footer
}
```

ウィンドウ最小幅は `本文 320 + (左ペイン幅 + 1)` として、左ペインを開いているぶんだけ動的に広がります。
