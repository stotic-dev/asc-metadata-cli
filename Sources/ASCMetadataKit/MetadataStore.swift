import Foundation

/// リポジトリ内で管理するメタ情報
public struct ReleaseMetadata: Sendable {
    /// locale (例: "ja", "en-US") をキーとしたリリースノート本文
    public let whatsNewByLocale: [String: String]
}

public enum MetadataError: Error, CustomStringConvertible {
    case directoryNotFound(String)
    case noReleaseNotes(String)

    public var description: String {
        switch self {
        case .directoryNotFound(let path):
            return "メタ情報ディレクトリが見つかりません: \(path)"
        case .noReleaseNotes(let path):
            return "リリースノートが 1 件も見つかりません。{locale}/release_notes.txt の構造で配置してください: \(path)"
        }
    }
}

/// `{metadata-dir}/{locale}/release_notes.txt` のディレクトリ構造からメタ情報を読み込む
public enum MetadataStore {
    public static let releaseNotesFileName = "release_notes.txt"

    public static func load(from directory: URL) throws -> ReleaseMetadata {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw MetadataError.directoryNotFound(directory.path)
        }

        var whatsNewByLocale: [String: String] = [:]
        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        for entry in entries {
            guard try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                continue
            }
            let noteURL = entry.appendingPathComponent(releaseNotesFileName)
            guard fileManager.fileExists(atPath: noteURL.path) else { continue }
            let text = try String(contentsOf: noteURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            whatsNewByLocale[entry.lastPathComponent] = text
        }

        guard !whatsNewByLocale.isEmpty else {
            throw MetadataError.noReleaseNotes(directory.path)
        }
        return ReleaseMetadata(whatsNewByLocale: whatsNewByLocale)
    }
}
