#!/usr/bin/env bash
set -euo pipefail

# MemontoMori アンインストーラ
#
# 既定では、作成したメモをアクセスしやすい場所（デスクトップ）に救い出してから、
# アプリ本体・設定・サンドボックスコンテナを丸ごと削除します。
# 「メモは手元に残す。MemontoMori 関連は完全に消す」を既定の動作にしています。
#
# Usage:
#   scripts/uninstall.sh              メモを Desktop へ退避してからアプリ一式を削除（確認あり）
#   scripts/uninstall.sh --yes        確認なしで実行
#   scripts/uninstall.sh --purge      メモも退避せずコンテナごと完全削除（要最終確認）
#   scripts/uninstall.sh --artifacts  リポジトリ内のビルド生成物 (./build, ./dist) も削除
#
# フラグは併用可能。--purge は元に戻せないため --yes を付けても最終確認を求めます。

APP_NAME="MemontoMori"
BUNDLE_ID="kimi8-lapi16.MemontoMori"
INSTALL_PATH="/Applications/${APP_NAME}.app"
CONTAINER="${HOME}/Library/Containers/${BUNDLE_ID}"

# サンドボックスコンテナ内のメモ保存先。
MEMO_DIR="${CONTAINER}/Data/Documents/${APP_NAME}"
MEMO_RESCUE_DIR="${HOME}/Desktop/${APP_NAME}-memos-$(date +%Y%m%d-%H%M%S)"

ASSUME_YES=0
PURGE=0
CLEAN_ARTIFACTS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) ASSUME_YES=1; shift ;;
    --purge) PURGE=1; shift ;;
    --artifacts) CLEAN_ARTIFACTS=1; shift ;;
    -h|--help) sed -n '3,17p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

# MemontoMori 関連で削除するもの一式（サンドボックス内 + 非サンドボックスの保険）。
REMOVE_PATHS=(
  "${INSTALL_PATH}"
  "${CONTAINER}"
  "${HOME}/Library/Preferences/${BUNDLE_ID}.plist"
  "${HOME}/Library/Saved Application State/${BUNDLE_ID}.savedState"
  "${HOME}/Library/Caches/${BUNDLE_ID}"
  "${HOME}/Library/HTTPStorages/${BUNDLE_ID}"
)

echo "==> ${APP_NAME} のアンインストールを開始します"
echo

# メモの有無を確認。
has_memos=0
if [[ -d "${MEMO_DIR}" ]] && [[ -n "$(ls -A "${MEMO_DIR}" 2>/dev/null)" ]]; then
  has_memos=1
fi

echo "削除対象（MemontoMori 関連を丸ごと）:"
for p in "${REMOVE_PATHS[@]}"; do
  [[ -e "${p}" ]] && echo "  - ${p}"
done
[[ "${CLEAN_ARTIFACTS}" -eq 1 ]] && echo "  - ビルド生成物: ./build, ./dist"
echo

if [[ "${has_memos}" -eq 1 ]]; then
  if [[ "${PURGE}" -eq 1 ]]; then
    echo "⚠️  --purge のためメモも退避せず削除します（元に戻せません）:"
    echo "     ${MEMO_DIR}"
  else
    echo "✅ メモは残します。次の場所へ退避してからアプリを削除します:"
    echo "     ${MEMO_DIR}"
    echo "       → ${MEMO_RESCUE_DIR}"
  fi
  echo
fi

# 確認プロンプト（--yes でスキップ。ただし --purge かつメモありは必ず確認）。
if [[ "${ASSUME_YES}" -eq 0 ]] || { [[ "${PURGE}" -eq 1 ]] && [[ "${has_memos}" -eq 1 ]]; }; then
  read -r -p "続行しますか? [y/N] " reply
  case "${reply}" in
    y|Y|yes|YES) ;;
    *) echo "中止しました。"; exit 0 ;;
  esac
fi

echo
echo "==> 起動中のインスタンスを終了..."
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
# メニューバーアプリなので念のため残プロセスも落とす。
pkill -x "${APP_NAME}" >/dev/null 2>&1 || true
sleep 1

# メモを先に退避（コピーが成功した場合のみ削除へ進む）。
rescued=0
if [[ "${has_memos}" -eq 1 ]] && [[ "${PURGE}" -eq 0 ]]; then
  echo "==> メモを退避: ${MEMO_RESCUE_DIR}"
  mkdir -p "${MEMO_RESCUE_DIR}"
  if cp -R "${MEMO_DIR}/." "${MEMO_RESCUE_DIR}/"; then
    rescued=1
  else
    echo "Error: メモの退避に失敗しました。安全のため削除を中止します。" >&2
    echo "       メモはそのまま残っています: ${MEMO_DIR}" >&2
    exit 1
  fi
fi

for p in "${REMOVE_PATHS[@]}"; do
  if [[ -e "${p}" ]]; then
    echo "==> 削除: ${p}"
    rm -rf "${p}"
  fi
done

# 設定キャッシュを確実に無効化（サンドボックスでも保険として）。
defaults delete "${BUNDLE_ID}" >/dev/null 2>&1 || true

if [[ "${CLEAN_ARTIFACTS}" -eq 1 ]]; then
  cd "$(dirname "$0")/.."
  echo "==> ビルド生成物を削除: ./build, ./dist"
  rm -rf ./build ./dist
fi

echo
echo "==> 完了しました。MemontoMori 関連は削除しました。"
if [[ "${rescued}" -eq 1 ]]; then
  echo "    メモはこちらに残してあります: ${MEMO_RESCUE_DIR}"
fi
