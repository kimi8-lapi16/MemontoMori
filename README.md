# MemontoMori

macOS のメニューバー常駐アプリ。

## インストール

1. [Releases](../../releases) ページから最新の `MemontoMori-x.y.z.dmg` をダウンロード。
2. DMG を開き、`MemontoMori.app` を `Applications` フォルダにドラッグ。
3. 初回起動時、Apple の署名がないため Gatekeeper に止められます。以下のいずれかで開いてください。
   - **方法 A**: `Applications` から `MemontoMori` を **右クリック → 開く** → 確認ダイアログで **開く** を押す。
   - **方法 B**: 一度起動を試した後、**システム設定 → プライバシーとセキュリティ** を開き、画面下部に出る「"MemontoMori" は開発元を確認できないためブロックされました」の横の **このまま開く** を押す。
4. 一度許可すれば、以降は通常通りダブルクリックで起動できます。

> このアプリは Apple Developer Program に加入していない開発者がビルドしているため、未署名 (ad-hoc 署名) で配布されています。動作上の問題はありません。

## 開発者向け

### ローカルビルド

```sh
# DMG を dist/ に作成
./scripts/build-dmg.sh

# DMG を作って、自分の /Applications に展開してそのまま起動
./scripts/build-dmg.sh --install
```

必要要件: Xcode（macOS）。追加の Homebrew パッケージは不要です。

### リリース手順

1. `MemontoMori.xcodeproj/project.pbxproj` の `MARKETING_VERSION` を更新。
2. タグを切って push。
   ```sh
   git tag v1.0.0
   git push origin v1.0.0
   ```
3. GitHub Actions (`.github/workflows/release.yml`) が自動的に macOS runner で DMG をビルドし、Releases に添付します。

`workflow_dispatch` から手動実行することも可能です（その場合は Release は作られず、Actions 上の artifact として DMG が取得できます）。
