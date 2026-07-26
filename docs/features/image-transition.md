---
id: image-transition
title: 画像切り替えアニメーション
sidebar_label: 画像切り替えアニメーション
sidebar_position: 6
description: 画像メモの切り替え時にフェードなどのアニメーションを適用する。
---

# 画像切り替えアニメーション

テキストメモは即時切り替えのままに、画像メモが絡む切り替えにだけアニメーションを適用します。適用するアニメーションは設定パネルのセレクトボックスから選択できます。

## 使い方

設定パネルの「動作設定 > 画像切り替え」で選択します。選択肢は次のとおりです。

| 選択肢 | 動き |
| --- | --- |
| なし（即時切り替え） | 従来どおりパッと切り替え |
| フェード（既定値） | クロスフェードで切り替え |
| スライド（横） | 旧画像が左へ抜け、新画像が右から入る |
| スライド（縦） | 旧画像が上へ抜け、新画像が下から入る |
| ズーム | 縮小フェードアウト + 拡大フェードイン |

選択内容は `UserDefaults` に保存され、次回起動時も維持されます。

## 適用条件

- 切り替えの **前後どちらかが画像** のときだけアニメーションします。
- テキスト → テキストの切り替えは従来どおり即時です（編集の邪魔をしないため）。
- 自動ローテーションによる送りも、フッターの `←` / `→` ボタンによる手動送りも対象です。

## 仕組み

`ImageTransitionStyle` enum が選択肢・`AnyTransition`・`Animation` を一元管理し、`MemoStore.imageTransition` として永続化されます。

`ContentView` は `rotation.currentID` を直接表示せず、`displayedID` という `@State` を経由させます。ID の変更を `onChange` で受け、画像が絡む場合のみ `withAnimation` で反映することで、SwiftUI の transition が発火します。

```swift title="ContentView.swift（抜粋）"
.onChange(of: rotation.currentID) { oldValue, newValue in
    let involvesImage = [oldValue, newValue]
        .compactMap { $0 }
        .contains { MemoEntry.isImage(id: $0) }
    if involvesImage, let animation = store.imageTransition.animation {
        withAnimation(animation) { displayedID = newValue }
    } else {
        displayedID = newValue
    }
}
```

切り替え途中は旧ビューと新ビューが同時に存在するため、メイン表示エリアは `ZStack` で重ね、`clipped()` でスライドのはみ出しを抑えています。
