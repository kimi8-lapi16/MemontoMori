# MemontoMori ドキュメントサイト

[Docusaurus](https://docusaurus.io/) 製のドキュメントサイトです。
ドキュメント本体はリポジトリ直下の [`../docs`](../docs) を参照しています
（`docusaurus.config.ts` の `docs.path` で指定）。

## ローカルで動かす

```sh
cd website
npm install
npm run start
```

`http://localhost:3000/MemontoMori/` が開きます。Markdown を編集すると
ホットリロードされます。

## 静的ビルド

```sh
npm run build      # build/ に静的サイトを生成
npm run serve      # 生成物をローカル配信して確認
```

## デプロイ

`master` への push で GitHub Actions
（[`.github/workflows/deploy-docs.yml`](../.github/workflows/deploy-docs.yml)）
が走り、GitHub Pages に公開されます。リポジトリの
**Settings → Pages → Source** を **GitHub Actions** にしておく必要があります。

## 構成

- `docusaurus.config.ts` — サイト設定（mermaid 有効化、`../docs` 参照、テーマ）
- `sidebars.ts` — `docs/` の構成と frontmatter から自動生成
- `src/css/custom.css` — テーマ色などの上書き
- `static/img/` — ロゴ・favicon（アプリアイコンを流用）
