import CryptoKit
import Foundation

public enum Checksum {
    /// App Store Connect API の sourceFileChecksum と同形式 (MD5 の hex 小文字) を計算する
    public static func md5Hex(of data: Data) -> String {
        Insecure.MD5.hash(data: data)
            .map { String(format: "%02hhx", $0) }
            .joined()
    }
}
