import Foundation
import Testing
@testable import ASCMetadataKit

@Test func PEMからBEGINEND行を除いたbase64DERに変換できる() {
    let pem = """
    -----BEGIN PRIVATE KEY-----
    MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEH
    BHkwdwIBAQQg1234567890abcdefghijk
    -----END PRIVATE KEY-----

    """

    let der = ASCClient.base64DER(fromPEM: pem)

    #expect(der == "MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg1234567890abcdefghijk")
}

@Test func メタデータディレクトリからリリースノートとスクリーンショットを読み込める() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }

    let jaDirectory = root.appendingPathComponent("ja")
    try FileManager.default.createDirectory(at: jaDirectory, withIntermediateDirectories: true)
    try "不具合を修正しました\n".write(
        to: jaDirectory.appendingPathComponent(MetadataStore.releaseNotesFileName),
        atomically: true,
        encoding: .utf8
    )
    // スクリーンショットはファイル名昇順で読み込まれ、画像以外のファイルは無視される
    let displayTypeDirectory = jaDirectory
        .appendingPathComponent(MetadataStore.screenshotsDirectoryName)
        .appendingPathComponent("APP_IPHONE_67")
    try FileManager.default.createDirectory(at: displayTypeDirectory, withIntermediateDirectories: true)
    for fileName in ["02_player.png", "01_home.png", ".DS_Store"] {
        try Data("dummy".utf8).write(to: displayTypeDirectory.appendingPathComponent(fileName))
    }
    // 空のリリースノートしかない locale は読み込み対象外になる
    let enDirectory = root.appendingPathComponent("en-US")
    try FileManager.default.createDirectory(at: enDirectory, withIntermediateDirectories: true)
    try "".write(
        to: enDirectory.appendingPathComponent(MetadataStore.releaseNotesFileName),
        atomically: true,
        encoding: .utf8
    )

    let metadata = try MetadataStore.load(from: root)

    #expect(metadata.whatsNewByLocale == ["ja": "不具合を修正しました"])
    #expect(metadata.screenshotSetsByLocale.keys.sorted() == ["ja"])
    let sets = try #require(metadata.screenshotSetsByLocale["ja"])
    #expect(sets.map(\.displayType) == ["APP_IPHONE_67"])
    #expect(sets[0].files.map(\.lastPathComponent) == ["01_home.png", "02_player.png"])
}

@Test func MD5チェックサムをhex小文字で計算できる() {
    let checksum = Checksum.md5Hex(of: Data("abc".utf8))

    #expect(checksum == "900150983cd24fb0d6963f7d28e17f72")
}
