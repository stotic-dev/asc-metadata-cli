import ArgumentParser
import ASCMetadataKit
import Foundation

@main
struct ASCMetadataCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "asc-metadata-cli",
        abstract: "App Store Connect の新バージョン作成とメタ情報更新を行う CLI",
        subcommands: [Sync.self],
        defaultSubcommand: Sync.self
    )
}

struct Sync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "指定バージョンを作成 (存在すれば再利用) し、リリースノートとスクリーンショットを同期する"
    )

    @Option(help: "対象アプリの bundle ID (例: jp.pivotmedia.pivot)")
    var bundleId: String

    @Option(help: "作成・更新するバージョン (例: 6.7.0)")
    var version: String

    @Option(help: "メタ情報ディレクトリ。{locale}/release_notes.txt の構造で配置する")
    var metadataDir: String

    @Option(help: "プラットフォーム (IOS / MAC_OS / TV_OS / VISION_OS)")
    var platform: String = "IOS"

    @Flag(help: "API への書き込みを行わず、実行予定の操作のみ表示する")
    var dryRun: Bool = false

    func run() async throws {
        let credentials = try Credentials.fromEnvironment()
        let metadata = try MetadataStore.load(from: URL(fileURLWithPath: metadataDir))
        let locales = metadata.whatsNewByLocale.keys.sorted()
        print("リリースノート読込: \(locales.joined(separator: ", "))")
        for (locale, sets) in metadata.screenshotSetsByLocale.sorted(by: { $0.key < $1.key }) {
            let summary = sets.map { "\($0.displayType) \($0.files.count) 枚" }.joined(separator: ", ")
            print("スクリーンショット読込: \(locale) (\(summary))")
        }

        let client = try ASCClient(
            keyID: credentials.keyID,
            issuerID: credentials.issuerID,
            privateKeyPEM: credentials.privateKeyPEM
        )

        guard let app = try await client.findApp(bundleID: bundleId) else {
            throw CLIError("bundle ID \(bundleId) のアプリが見つかりません")
        }
        print("アプリ: \(app.name ?? bundleId) (id: \(app.id))")

        let targetVersion: ASCClient.Version
        if let existing = try await client.findVersion(
            appID: app.id,
            versionString: version,
            platform: platform
        ) {
            print("既存バージョン \(version) を再利用します (状態: \(existing.state ?? "不明"))")
            targetVersion = existing
        } else if dryRun {
            print("[dry-run] バージョン \(version) を新規作成します")
            for locale in locales {
                print("[dry-run] \(locale): リリースノートを設定します")
            }
            for (locale, sets) in metadata.screenshotSetsByLocale.sorted(by: { $0.key < $1.key }) {
                for set in sets {
                    print("[dry-run] \(locale)/\(set.displayType): スクリーンショット \(set.files.count) 枚をアップロードします")
                }
            }
            return
        } else {
            targetVersion = try await client.createVersion(
                appID: app.id,
                versionString: version,
                platform: platform
            )
            print("バージョン \(version) を新規作成しました")
        }

        try await syncReleaseNotes(client: client, versionID: targetVersion.id, metadata: metadata)
        try await syncScreenshots(client: client, versionID: targetVersion.id, metadata: metadata)
        print("完了")
    }

    private func syncReleaseNotes(
        client: ASCClient,
        versionID: String,
        metadata: ReleaseMetadata
    ) async throws {
        let existingLocalizations = try await client.localizations(versionID: versionID)
        for (locale, whatsNew) in metadata.whatsNewByLocale.sorted(by: { $0.key < $1.key }) {
            if let localization = existingLocalizations.first(where: { $0.locale == locale }) {
                if localization.whatsNew == whatsNew {
                    print("\(locale): 変更なしのためスキップ")
                    continue
                }
                if dryRun {
                    print("[dry-run] \(locale): リリースノートを更新します")
                    continue
                }
                try await client.updateLocalization(id: localization.id, whatsNew: whatsNew)
                print("\(locale): リリースノートを更新しました")
            } else {
                if dryRun {
                    print("[dry-run] \(locale): ローカリゼーションを新規作成します")
                    continue
                }
                _ = try await client.createLocalization(
                    versionID: versionID,
                    locale: locale,
                    whatsNew: whatsNew
                )
                print("\(locale): ローカリゼーションを作成してリリースノートを設定しました")
            }
        }
    }

    private func syncScreenshots(
        client: ASCClient,
        versionID: String,
        metadata: ReleaseMetadata
    ) async throws {
        guard !metadata.screenshotSetsByLocale.isEmpty else { return }
        // リリースノート同期で新規作成されたローカリゼーションを含めて取り直す
        let localizations = try await client.localizations(versionID: versionID)
        for (locale, sets) in metadata.screenshotSetsByLocale.sorted(by: { $0.key < $1.key }) {
            let localizationID: String
            if let existing = localizations.first(where: { $0.locale == locale }) {
                localizationID = existing.id
            } else if dryRun {
                print("[dry-run] \(locale): ローカリゼーションを新規作成します")
                for set in sets {
                    print("[dry-run] \(locale)/\(set.displayType): スクリーンショット \(set.files.count) 枚をアップロードします")
                }
                continue
            } else {
                let created = try await client.createLocalization(
                    versionID: versionID,
                    locale: locale,
                    whatsNew: metadata.whatsNewByLocale[locale]
                )
                print("\(locale): ローカリゼーションを作成しました")
                localizationID = created.id
            }

            let remoteSets = try await client.screenshotSets(localizationID: localizationID)
            for set in sets {
                try await syncScreenshotSet(
                    client: client,
                    locale: locale,
                    localizationID: localizationID,
                    set: set,
                    remoteSet: remoteSets.first { $0.displayType == set.displayType }
                )
            }
        }
    }

    private func syncScreenshotSet(
        client: ASCClient,
        locale: String,
        localizationID: String,
        set: ScreenshotSetMetadata,
        remoteSet: ASCClient.ScreenshotSet?
    ) async throws {
        let label = "\(locale)/\(set.displayType)"
        let localFiles = try set.files.map { url in
            (fileName: url.lastPathComponent, checksum: Checksum.md5Hex(of: try Data(contentsOf: url)))
        }

        if let remoteSet {
            let remote = try await client.screenshots(screenshotSetID: remoteSet.id)
            let isSame = remote.count == localFiles.count && zip(remote, localFiles).allSatisfy {
                $0.fileName == $1.fileName && $0.sourceFileChecksum == $1.checksum
            }
            if isSame {
                print("\(label): 変更なしのためスキップ")
                return
            }
            if dryRun {
                print("[dry-run] \(label): 既存 \(remote.count) 枚を削除して \(localFiles.count) 枚をアップロードします")
                return
            }
            for screenshot in remote {
                try await client.deleteScreenshot(id: screenshot.id)
            }
            for file in set.files {
                try await client.uploadScreenshot(screenshotSetID: remoteSet.id, fileURL: file)
            }
            print("\(label): 既存 \(remote.count) 枚を置き換えて \(localFiles.count) 枚をアップロードしました")
        } else {
            if dryRun {
                print("[dry-run] \(label): セットを作成して \(localFiles.count) 枚をアップロードします")
                return
            }
            let created = try await client.createScreenshotSet(
                localizationID: localizationID,
                displayType: set.displayType
            )
            for file in set.files {
                try await client.uploadScreenshot(screenshotSetID: created.id, fileURL: file)
            }
            print("\(label): セットを作成して \(localFiles.count) 枚をアップロードしました")
        }
    }
}

struct Credentials {
    let keyID: String
    let issuerID: String
    let privateKeyPEM: String

    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Credentials {
        guard let keyID = environment["ASC_KEY_ID"], !keyID.isEmpty else {
            throw CLIError("環境変数 ASC_KEY_ID が未設定です")
        }
        guard let issuerID = environment["ASC_ISSUER_ID"], !issuerID.isEmpty else {
            throw CLIError("環境変数 ASC_ISSUER_ID が未設定です")
        }
        let privateKeyPEM: String
        if let content = environment["ASC_PRIVATE_KEY"], !content.isEmpty {
            privateKeyPEM = content
        } else if let path = environment["ASC_PRIVATE_KEY_PATH"], !path.isEmpty {
            privateKeyPEM = try String(contentsOfFile: path, encoding: .utf8)
        } else {
            throw CLIError("環境変数 ASC_PRIVATE_KEY (p8 の中身) か ASC_PRIVATE_KEY_PATH (p8 のパス) を設定してください")
        }
        return Credentials(keyID: keyID, issuerID: issuerID, privateKeyPEM: privateKeyPEM)
    }
}

struct CLIError: Error, CustomStringConvertible {
    let description: String

    init(_ message: String) {
        description = message
    }
}
