import CryptoKit
import Foundation
import Testing
@testable import ASCMetadataKit

@Test func JWTの構造と署名が正しい() throws {
    let privateKey = P256.Signing.PrivateKey()
    let generator = ASCTokenGenerator(
        keyID: "KEY123",
        issuerID: "issuer-abc",
        privateKeyPEM: privateKey.pemRepresentation
    )

    let token = try generator.makeToken(now: Date(timeIntervalSince1970: 1_700_000_000))

    let parts = token.split(separator: ".")
    #expect(parts.count == 3)

    let header = try JSONSerialization.jsonObject(with: decodeBase64URL(parts[0])) as! [String: Any]
    #expect(header["alg"] as? String == "ES256")
    #expect(header["kid"] as? String == "KEY123")
    #expect(header["typ"] as? String == "JWT")

    let payload = try JSONSerialization.jsonObject(with: decodeBase64URL(parts[1])) as! [String: Any]
    #expect(payload["iss"] as? String == "issuer-abc")
    #expect(payload["aud"] as? String == "appstoreconnect-v1")
    #expect(payload["iat"] as? Int == 1_700_000_000)
    #expect(payload["exp"] as? Int == 1_700_000_600)

    let signature = try P256.Signing.ECDSASignature(rawRepresentation: decodeBase64URL(parts[2]))
    let signingInput = Data("\(parts[0]).\(parts[1])".utf8)
    #expect(privateKey.publicKey.isValidSignature(signature, for: signingInput))
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

private func decodeBase64URL(_ input: Substring) throws -> Data {
    var base64 = input
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    while base64.count % 4 != 0 {
        base64 += "="
    }
    return try #require(Data(base64Encoded: base64))
}
