# asc-metadata-cli

App Store Connect の新バージョン作成とメタ情報更新を行う Swift CLI ツール。

Xcode Cloud の Release ワークフローでの ipa アップロードと分業し、リポジトリ内で管理しているメタ情報（リリースノート等）を App Store Connect に同期することを目的としている。

## スコープ

- [x] 新バージョンの作成（既に存在する場合は再利用）
- [x] リリースノート（What's New）のロケール別同期
  - 変更がないロケールはスキップ
  - ローカリゼーションが存在しない場合は新規作成
- [x] スクリーンショット同期（ロケール × displayType 別）
  - ファイル名 + MD5 チェックサムが順序込みで一致するセットはスキップ
  - 差分があるセットは既存を全削除して再アップロード（fastlane deliver と同方式）
- [ ] ビルドのバージョン紐付け・審査提出（今後検討）

## 必要環境

- macOS 13+
- Swift 6.0+

## 依存ライブラリ

- [AppStoreConnect-Swift-SDK](https://github.com/AvdLee/appstoreconnect-swift-sdk): JWT 認証と App Store Connect API クライアント(OpenAPI 生成)。通信層はすべてこの SDK に委譲し、本ツールは「メタ情報の読み込み + 同期ロジック」のみを実装している
- [swift-argument-parser](https://github.com/apple/swift-argument-parser): CLI 引数パース

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
│   ├── release_notes.txt
│   └── screenshots/
│       ├── APP_IPHONE_67/
│       │   ├── 01_home.png
│       │   └── 02_player.png
│       └── APP_IPAD_PRO_3GEN_129/
│           └── 01_home.png
└── en-US/
    └── release_notes.txt
```

- ディレクトリ名は App Store Connect のロケール識別子（`ja`, `en-US` 等）に合わせる
- `release_notes.txt` が空のロケールはスキップされる
- `screenshots/` 配下のディレクトリ名は App Store Connect API の [screenshotDisplayType](https://developer.apple.com/documentation/appstoreconnectapi/screenshotdisplaytype)（`APP_IPHONE_67` 等）に合わせる
- スクリーンショットの表示順はファイル名昇順（`01_`, `02_` のような接頭辞で制御する）
- 対応拡張子は png / jpg / jpeg。それ以外のファイル（`.DS_Store` 等）は無視される
- `release_notes.txt` と `screenshots/` はどちらか一方だけでもよい

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
- スクリーンショットは displayType のディレクトリ単位で「全削除 → 再アップロード」する。App Store Connect 側だけで並び替え・差し替えした内容はリポジトリ側と差分が出た時点で上書きされる
- リポジトリに存在しない displayType / ロケールのスクリーンショットセットは削除しない（安全側に倒している）
- 画像サイズが displayType の要求解像度と一致しない場合、アップロード自体は成功するが App Store Connect 側の検証で `FAILED` になる
- App Store Connect API の OpenAPI spec ではスクリーンショット系エンドポイントが deprecated 指定されているため、ビルド時に deprecation 警告が出る（API 自体は現行で動作する。fastlane deliver も同じエンドポイントを使用）

## バイナリ配布

リリース時に、ビルド済みの実行可能ファイルを SwiftPM の [`.binaryTarget`](https://developer.apple.com/documentation/packagedescription/target/binarytarget(name:url:checksum:)) から参照できる `artifactbundle` 形式（zip）で配布する。利用側はソースからビルドせずに CLI を組み込める。

### 成果物の生成（メンテナ向け）

```sh
# arm64 / x86_64 の universal binary を ./binary/asc-metadata-cli に生成
make binary

# artifactbundle.zip と checksum を生成（リリース添付用）
make release VERSION=1.0.0
```

`binary/` 配下の生成物は追跡対象外（`.gitignore` 済み）。リリースは GitHub Actions の `Release` ワークフロー（`.github/workflows/release.yml`）を手動実行し、`version`（例: `1.0.0`）を入力する。ワークフローは universal binary をビルドし、`v<version>` タグを作成して `asc-metadata-cli.artifactbundle.zip` を GitHub Release に添付する。

### 利用側での組み込み

`make release` が出力した checksum を使い、依存パッケージの `Package.swift` に次を追加する。

```swift
.binaryTarget(
    name: "asc-metadata-cli",
    url: "https://github.com/stotic-dev/asc-metadata-cli/releases/download/v1.0.0/asc-metadata-cli.artifactbundle.zip",
    checksum: "<make release が出力した checksum>"
)
```

## テスト

```sh
swift test
```
