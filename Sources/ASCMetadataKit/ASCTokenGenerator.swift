import CryptoKit
import Foundation

/// App Store Connect API の認証用 JWT (ES256) を生成する
public struct ASCTokenGenerator: Sendable {
    /// トークンの有効期間。App Store Connect API の上限は 20 分
    private static let tokenLifetime: TimeInterval = 10 * 60

    private let keyID: String
    private let issuerID: String
    private let privateKeyPEM: String

    public init(keyID: String, issuerID: String, privateKeyPEM: String) {
        self.keyID = keyID
        self.issuerID = issuerID
        self.privateKeyPEM = privateKeyPEM
    }

    public func makeToken(now: Date = Date()) throws -> String {
        struct Header: Encodable {
            let alg = "ES256"
            let kid: String
            let typ = "JWT"
        }
        struct Payload: Encodable {
            let iss: String
            let iat: Int
            let exp: Int
            let aud: String
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let header = try encoder.encode(Header(kid: keyID))
        let payload = try encoder.encode(Payload(
            iss: issuerID,
            iat: Int(now.timeIntervalSince1970),
            exp: Int(now.addingTimeInterval(Self.tokenLifetime).timeIntervalSince1970),
            aud: "appstoreconnect-v1"
        ))

        let signingInput = "\(Self.base64URL(header)).\(Self.base64URL(payload))"
        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
        let signature = try privateKey.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(Self.base64URL(signature.rawRepresentation))"
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
