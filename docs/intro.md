---
id: intro
title: MemontoMori とは
sidebar_label: はじめに
sidebar_position: 1
slug: /
description: macOS メニューバー常駐型のメモ＆ローテーション表示アプリ MemontoMori の概要。
keywords: [macOS, menu bar, SwiftUI, memo, screensaver, markdown]
---

# MemontoMori

**MemontoMori** は macOS のメニューバーに常駐するメモアプリです。
ただ書くだけでなく、一定時間操作がないと保存済みメモを **自動でローテーション表示**（スクリーンセーバー的に巡回）するのが最大の特徴です。

> _Memento mori_（死を想え）をもじったネーミングで、「書いたまま忘れてしまうメモを、勝手に目の前に呼び戻す」ことを狙っています。

:::tip このドキュメントについて
このサイトは、これまでの開発（PR #1〜#8）で積み上がった **大きめの変更** を機能単位で Docusaurus 向け Markdown に書き出したものです。各ページは実際のソースコード（`MemontoMori/*.swift`）の挙動に対応しています。
:::

## 3行で分かる MemontoMori

- 📝 メニューバーのアイコンから、Markdown / プレーンテキストのメモをその場で編集。
- 🔄 アイドル状態が続くと、有効なメモを設定間隔で自動巡回表示。
- 👁️ `.md` ファイルはワンクリックで **編集 ⇄ プレビュー** を切り替え。

## 主な機能

| 機能 | 概要 | 詳細 |
| --- | --- | --- |
| 常に最前面（ピン留め） | ウィンドウを floating レベルに固定 | [Always on Top](./features/always-on-top.md) |
| メモのローテーション表示 | アイドル検知 → 自動巡回 | [Memo Rotation](./features/memo-rotation.md) |
| サブフォルダ切り替え | ローテーション対象ディレクトリを選択 | [Subdirectories](./features/subdirectories.md) |
| Markdown プレビュー | 自前パーサで `NSAttributedString` 描画 | [Markdown Preview](./features/markdown-preview.md) |
| 分割パネル設定 | メモ編集＋設定を横並び表示 | [Split-Panel Settings](./features/split-panel-settings.md) |
| DMG 配布 / リリース | ローカルビルド & GitHub Actions | [Build & Release](./development/build-and-release.md) |

## データの置き場所

メモの実体は、ユーザーの `Documents/MemontoMori/` 配下に置かれた `.md` / `.txt` ファイルそのものです。
アプリ独自のデータベースは持たず、ファイルが正（source of truth）です。表示順や有効/無効といったメタ情報のみ `UserDefaults` に保存します。

```
~/Documents/MemontoMori/
├── todo.md
├── ideas.md
└── work/            ← サブフォルダ（切り替え対象）
    └── standup.md
```

:::info 設計思想
アプリが落ちても、アンインストールしても、メモは普通のテキストファイルとして残ります。Finder や他のエディタからの編集も尊重し、起動時に再スキャンします。
:::

## 次に読む

- アプリ全体の構造を知りたい → [アーキテクチャ](./architecture.md)
- すぐ使いたい → [Build & Release](./development/build-and-release.md)
</content>
</invoke>
