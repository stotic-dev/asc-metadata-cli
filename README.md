# asc-metadata-cli

App Store Connect の新バージョン作成とメタ情報更新を行う Swift CLI ツール。

Xcode Cloud の Release ワークフローでの ipa アップロードと分業し、リポジトリ内で管理しているメタ情報（リリースノート等）を App Store Connect に同期することを目的としている。

## MVP スコープ

- [x] 新バージョンの作成（既に存在する場合は再利用）
- [x] リリースノート（What's New）のロケール別同期
  - 変更がないロケールはスキップ
  - ローカリゼーションが存在しない場合は新規作成
- [ ] スクリーンショット同期（第 2 段で対応予定）
- [ ] ビルドのバージョン紐付け・審査提出（第 2 段以降で検討）

## 必要環境

- macOS 13+
- Swift 6.0+

## セットアップ

### 1. App Store Connect API キーの発行

App Store Connect → ユーザとアクセス → 統合 → App Store Connect API でキーを発行し、以下を控える。

- Key ID
- Issuer ID
- 秘密鍵（`.p8` ファイル）

ロールは「App Manager」以上が必要。

### 2. 環境変数の設定

| 環境変数 | 内容 |
|---|---|
| `ASC_KEY_ID` | API キーの Key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_PRIVATE_KEY` | `.p8` ファイルの中身（PEM 文字列）。CI のシークレット向け |
| `ASC_PRIVATE_KEY_PATH` | `.p8` ファイルのパス。ローカル実行向け。`ASC_PRIVATE_KEY` が優先される |

## 使い方

```sh
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export ASC_PRIVATE_KEY_PATH=~/keys/AuthKey_XXXXXXXXXX.p8

swift run asc-metadata-cli sync \
  --bundle-id jp.pivotmedia.pivot \
  --version 6.7.0 \
  --metadata-dir ./Example/metadata
```

`--dry-run` を付けると API への書き込みを行わず、実行予定の操作のみ表示する。

### メタ情報のディレクトリ構造

```
metadata/
├── ja/
│   └── release_notes.txt
└── en-US/
    └── release_notes.txt
```

- ディレクトリ名は App Store Connect のロケール識別子（`ja`, `en-US` 等）に合わせる
- `release_notes.txt` が空のロケールはスキップされる

## Xcode Cloud との連携方針

Xcode Cloud には「ipa アップロード完了後」のフックが存在しないため、以下の分業を想定している。

- **ipa のアップロード**: Xcode Cloud の Release ワークフロー（既存のまま）
- **バージョン作成・メタ情報同期**: 本 CLI。バージョン作成とメタ情報更新はビルドの存在に依存しないため、`ci_post_xcodebuild.sh` からの実行、または GitHub Actions からの実行のどちらでも成立する

`ci_post_xcodebuild.sh` から実行する場合の例:

```sh
if [ "$CI_WORKFLOW" = "Release" ] && [ -n "$CI_APP_STORE_SIGNED_APP_PATH" ]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$CI_PRIMARY_REPOSITORY_PATH/Pivot_iOS/Info.plist")
    swift run --package-path tools/asc-metadata-cli asc-metadata-cli sync \
        --bundle-id jp.pivotmedia.pivot \
        --version "$VERSION" \
        --metadata-dir "$CI_PRIMARY_REPOSITORY_PATH/metadata"
fi
```

## 制約・注意事項

- アプリの**初回バージョン**にはリリースノート（What's New）を設定できない（App Store Connect の仕様）
- ビルドとバージョンの紐付けはビルド処理完了（通常 10〜30 分）を待つ必要があるため、MVP では扱わない
- 対象バージョンが編集不可の状態（審査中等）の場合、メタ情報の更新は API エラーになる

## テスト

```sh
swift test
```
