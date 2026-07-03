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

@Test func メタデータディレクトリからリリースノートを読み込める() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }

    let jaDirectory = root.appendingPathComponent("ja")
    try FileManager.default.createDirectory(at: jaDirectory, withIntermediateDirectories: true)
    try "不具合を修正しました\n".write(
        to: jaDirectory.appendingPathComponent(MetadataStore.releaseNotesFileName),
        atomically: true,
        encoding: .utf8
    )
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
}
