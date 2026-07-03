import AppStoreConnect_Swift_SDK
import Foundation

public enum ASCClientError: Error, CustomStringConvertible {
    case invalidPlatform(String)
    case invalidScreenshotDisplayType(String)
    case missingUploadOperations(fileName: String)
    case chunkUploadFailed(fileName: String, statusCode: Int?)

    public var description: String {
        switch self {
        case .invalidPlatform(let value):
            let supported = Platform.allCases.map(\.rawValue).joined(separator: " / ")
            return "不正なプラットフォームです: \(value) (指定可能: \(supported))"
        case .invalidScreenshotDisplayType(let value):
            let supported = ScreenshotDisplayType.allCases.map(\.rawValue).joined(separator: " / ")
            return "不正な screenshotDisplayType です: \(value) (指定可能: \(supported))"
        case .missingUploadOperations(let fileName):
            return "アップロード先が予約レスポンスに含まれていません: \(fileName)"
        case .chunkUploadFailed(let fileName, let statusCode):
            return "スクリーンショットのアップロードに失敗しました: \(fileName) (status: \(statusCode.map(String.init) ?? "不明"))"
        }
    }
}

/// AppStoreConnect-Swift-SDK の薄いラッパー。
/// MVP で必要なバージョン作成とリリースノート更新の操作のみ公開している
public struct ASCClient {
    public struct App: Sendable {
        public let id: String
        public let name: String?
    }

    public struct Version: Sendable {
        public let id: String
        public let versionString: String
        public let state: String?
    }

    public struct Localization: Sendable {
        public let id: String
        public let locale: String
        public let whatsNew: String?
    }

    public struct ScreenshotSet: Sendable {
        public let id: String
        public let displayType: String
    }

    public struct Screenshot: Sendable {
        public let id: String
        public let fileName: String?
        public let sourceFileChecksum: String?
    }

    private let provider: APIProvider

    public init(keyID: String, issuerID: String, privateKeyPEM: String) throws {
        let configuration = try APIConfiguration(
            issuerID: issuerID,
            privateKeyID: keyID,
            privateKey: Self.base64DER(fromPEM: privateKeyPEM)
        )
        provider = APIProvider(configuration: configuration)
    }

    // MARK: - Apps

    public func findApp(bundleID: String) async throws -> App? {
        let request = APIEndpoint.v1.apps.get(parameters: .init(filterBundleID: [bundleID]))
        let response = try await provider.request(request)
        guard let app = response.data.first(where: { $0.attributes?.bundleID == bundleID }) else {
            return nil
        }
        return App(id: app.id, name: app.attributes?.name)
    }

    // MARK: - App Store Versions

    public func findVersion(appID: String, versionString: String, platform: String) async throws -> Version? {
        let platform = try Self.platform(from: platform)
        let filterPlatform = APIEndpoint.V1.Apps.WithID.AppStoreVersions.GetParameters
            .FilterPlatform(rawValue: platform.rawValue)
        let request = APIEndpoint.v1.apps.id(appID).appStoreVersions.get(parameters: .init(
            filterPlatform: filterPlatform.map { [$0] },
            filterVersionString: [versionString]
        ))
        let response = try await provider.request(request)
        guard let version = response.data.first else { return nil }
        return Version(
            id: version.id,
            versionString: version.attributes?.versionString ?? versionString,
            state: version.attributes?.appStoreState?.rawValue
        )
    }

    public func createVersion(appID: String, versionString: String, platform: String) async throws -> Version {
        let body = AppStoreVersionCreateRequest(data: .init(
            type: .appStoreVersions,
            attributes: .init(platform: try Self.platform(from: platform), versionString: versionString),
            relationships: .init(app: .init(data: .init(type: .apps, id: appID)))
        ))
        let response = try await provider.request(APIEndpoint.v1.appStoreVersions.post(body))
        return Version(
            id: response.data.id,
            versionString: response.data.attributes?.versionString ?? versionString,
            state: response.data.attributes?.appStoreState?.rawValue
        )
    }

    // MARK: - App Store Version Localizations

    public func localizations(versionID: String) async throws -> [Localization] {
        let request = APIEndpoint.v1.appStoreVersions.id(versionID)
            .appStoreVersionLocalizations.get(parameters: .init(limit: 50))
        let response = try await provider.request(request)
        return response.data.compactMap { localization in
            guard let locale = localization.attributes?.locale else { return nil }
            return Localization(
                id: localization.id,
                locale: locale,
                whatsNew: localization.attributes?.whatsNew
            )
        }
    }

    public func updateLocalization(id: String, whatsNew: String) async throws {
        let body = AppStoreVersionLocalizationUpdateRequest(data: .init(
            type: .appStoreVersionLocalizations,
            id: id,
            attributes: .init(whatsNew: whatsNew)
        ))
        _ = try await provider.request(APIEndpoint.v1.appStoreVersionLocalizations.id(id).patch(body))
    }

    public func createLocalization(versionID: String, locale: String, whatsNew: String? = nil) async throws -> Localization {
        let body = AppStoreVersionLocalizationCreateRequest(data: .init(
            type: .appStoreVersionLocalizations,
            attributes: .init(locale: locale, whatsNew: whatsNew),
            relationships: .init(appStoreVersion: .init(data: .init(type: .appStoreVersions, id: versionID)))
        ))
        let response = try await provider.request(APIEndpoint.v1.appStoreVersionLocalizations.post(body))
        return Localization(
            id: response.data.id,
            locale: response.data.attributes?.locale ?? locale,
            whatsNew: response.data.attributes?.whatsNew
        )
    }

    // MARK: - App Screenshots
    //
    // SDK 生成コードはスクリーンショット系 API を OpenAPI spec の指定どおり deprecated として
    // 出力するため、以下のメソッドはビルド時に deprecation 警告が出る (API 自体は現行で動作する)

    public func screenshotSets(localizationID: String) async throws -> [ScreenshotSet] {
        let request = APIEndpoint.v1.appStoreVersionLocalizations.id(localizationID)
            .appScreenshotSets.get(parameters: .init(limit: 50))
        let response = try await provider.request(request)
        return response.data.compactMap { set in
            guard let displayType = set.attributes?.screenshotDisplayType else { return nil }
            return ScreenshotSet(id: set.id, displayType: displayType.rawValue)
        }
    }

    public func createScreenshotSet(localizationID: String, displayType: String) async throws -> ScreenshotSet {
        let displayType = try Self.screenshotDisplayType(from: displayType)
        let body = AppScreenshotSetCreateRequest(data: .init(
            type: .appScreenshotSets,
            attributes: .init(screenshotDisplayType: displayType),
            relationships: .init(appStoreVersionLocalization: .init(
                data: .init(type: .appStoreVersionLocalizations, id: localizationID)
            ))
        ))
        let response = try await provider.request(APIEndpoint.v1.appScreenshotSets.post(body))
        return ScreenshotSet(
            id: response.data.id,
            displayType: response.data.attributes?.screenshotDisplayType?.rawValue ?? displayType.rawValue
        )
    }

    public func screenshots(screenshotSetID: String) async throws -> [Screenshot] {
        let request = APIEndpoint.v1.appScreenshotSets.id(screenshotSetID)
            .appScreenshots.get(parameters: .init(limit: 50))
        let response = try await provider.request(request)
        return response.data.map { screenshot in
            Screenshot(
                id: screenshot.id,
                fileName: screenshot.attributes?.fileName,
                sourceFileChecksum: screenshot.attributes?.sourceFileChecksum
            )
        }
    }

    public func deleteScreenshot(id: String) async throws {
        try await provider.request(APIEndpoint.v1.appScreenshots.id(id).delete)
    }

    /// 予約 → チャンクアップロード → MD5 コミットの 3 段階でスクリーンショットをアップロードする
    public func uploadScreenshot(screenshotSetID: String, fileURL: URL) async throws {
        let data = try Data(contentsOf: fileURL)
        let fileName = fileURL.lastPathComponent

        let reserveBody = AppScreenshotCreateRequest(data: .init(
            type: .appScreenshots,
            attributes: .init(fileSize: data.count, fileName: fileName),
            relationships: .init(appScreenshotSet: .init(
                data: .init(type: .appScreenshotSets, id: screenshotSetID)
            ))
        ))
        let reserved = try await provider.request(APIEndpoint.v1.appScreenshots.post(reserveBody))

        guard let operations = reserved.data.attributes?.uploadOperations, !operations.isEmpty else {
            throw ASCClientError.missingUploadOperations(fileName: fileName)
        }
        for operation in operations {
            try await uploadChunk(of: data, operation: operation, fileName: fileName)
        }

        let commitBody = AppScreenshotUpdateRequest(data: .init(
            type: .appScreenshots,
            id: reserved.data.id,
            attributes: .init(sourceFileChecksum: Checksum.md5Hex(of: data), isUploaded: true)
        ))
        _ = try await provider.request(APIEndpoint.v1.appScreenshots.id(reserved.data.id).patch(commitBody))
    }

    private func uploadChunk(of data: Data, operation: UploadOperation, fileName: String) async throws {
        guard let urlString = operation.url,
              let url = URL(string: urlString),
              let offset = operation.offset,
              let length = operation.length
        else {
            throw ASCClientError.missingUploadOperations(fileName: fileName)
        }
        var request = URLRequest(url: url)
        request.httpMethod = operation.method ?? "PUT"
        for header in operation.requestHeaders ?? [] {
            if let name = header.name, let value = header.value {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }
        let chunk = data.subdata(in: offset ..< min(offset + length, data.count))
        let (_, response) = try await URLSession.shared.upload(for: request, from: chunk)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw ASCClientError.chunkUploadFailed(
                fileName: fileName,
                statusCode: (response as? HTTPURLResponse)?.statusCode
            )
        }
    }

    // MARK: - Private

    private static func screenshotDisplayType(from rawValue: String) throws -> ScreenshotDisplayType {
        guard let displayType = ScreenshotDisplayType(rawValue: rawValue) else {
            throw ASCClientError.invalidScreenshotDisplayType(rawValue)
        }
        return displayType
    }

    private static func platform(from rawValue: String) throws -> Platform {
        guard let platform = Platform(rawValue: rawValue) else {
            throw ASCClientError.invalidPlatform(rawValue)
        }
        return platform
    }

    /// APIConfiguration は BEGIN/END 行を除いた base64 (DER) 形式を要求するため、PEM から変換する
    static func base64DER(fromPEM pem: String) -> String {
        pem.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("PRIVATE KEY") }
            .joined()
    }
}
