import Foundation

/// リポジトリ内で管理するメタ情報
public struct ReleaseMetadata: Sendable {
    /// locale (例: "ja", "en-US") をキーとしたリリースノート本文
    public let whatsNewByLocale: [String: String]
    /// locale をキーとしたスクリーンショットセット (displayType 昇順)
    public let screenshotSetsByLocale: [String: [ScreenshotSetMetadata]]
}

/// 1 つの displayType に対応するスクリーンショット群
public struct ScreenshotSetMetadata: Sendable {
    /// App Store Connect API の screenshotDisplayType (例: "APP_IPHONE_67")
    public let displayType: String
    /// スクリーンショットファイル (ファイル名昇順 = 表示順)
    public let files: [URL]
}

public enum MetadataError: Error, CustomStringConvertible {
    case directoryNotFound(String)
    case noMetadata(String)

    public var description: String {
        switch self {
        case .directoryNotFound(let path):
            return "メタ情報ディレクトリが見つかりません: \(path)"
        case .noMetadata(let path):
            return "メタ情報が 1 件も見つかりません。{locale}/release_notes.txt または {locale}/screenshots/{DISPLAY_TYPE}/ の構造で配置してください: \(path)"
        }
    }
}

/// `{metadata-dir}/{locale}/` のディレクトリ構造からメタ情報を読み込む
///
/// ```
/// metadata/
/// ├── ja/
/// │   ├── release_notes.txt
/// │   └── screenshots/
/// │       └── APP_IPHONE_67/
/// │           ├── 01_home.png
/// │           └── 02_player.png
/// └── en-US/
///     └── release_notes.txt
/// ```
public enum MetadataStore {
    public static let releaseNotesFileName = "release_notes.txt"
    public static let screenshotsDirectoryName = "screenshots"
    public static let screenshotExtensions: Set<String> = ["png", "jpg", "jpeg"]

    public static func load(from directory: URL) throws -> ReleaseMetadata {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw MetadataError.directoryNotFound(directory.path)
        }

        var whatsNewByLocale: [String: String] = [:]
        var screenshotSetsByLocale: [String: [ScreenshotSetMetadata]] = [:]
        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        for entry in entries {
            guard try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                continue
            }
            let locale = entry.lastPathComponent

            let noteURL = entry.appendingPathComponent(releaseNotesFileName)
            if fileManager.fileExists(atPath: noteURL.path) {
                let text = try String(contentsOf: noteURL, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    whatsNewByLocale[locale] = text
                }
            }

            let sets = try loadScreenshotSets(in: entry.appendingPathComponent(screenshotsDirectoryName))
            if !sets.isEmpty {
                screenshotSetsByLocale[locale] = sets
            }
        }

        guard !whatsNewByLocale.isEmpty || !screenshotSetsByLocale.isEmpty else {
            throw MetadataError.noMetadata(directory.path)
        }
        return ReleaseMetadata(
            whatsNewByLocale: whatsNewByLocale,
            screenshotSetsByLocale: screenshotSetsByLocale
        )
    }

    private static func loadScreenshotSets(in screenshotsDirectory: URL) throws -> [ScreenshotSetMetadata] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: screenshotsDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return []
        }

        var sets: [ScreenshotSetMetadata] = []
        let displayTypeDirectories = try fileManager.contentsOfDirectory(
            at: screenshotsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        for displayTypeDirectory in displayTypeDirectories {
            guard try displayTypeDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                continue
            }
            let files = try fileManager.contentsOfDirectory(
                at: displayTypeDirectory,
                includingPropertiesForKeys: nil
            )
            .filter { screenshotExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard !files.isEmpty else { continue }
            sets.append(ScreenshotSetMetadata(
                displayType: displayTypeDirectory.lastPathComponent,
                files: files
            ))
        }
        return sets.sorted { $0.displayType < $1.displayType }
    }
}
