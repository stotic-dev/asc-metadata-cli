import AppStoreConnect_Swift_SDK
import Foundation

public enum ASCClientError: Error, CustomStringConvertible {
    case invalidPlatform(String)

    public var description: String {
        switch self {
        case .invalidPlatform(let value):
            let supported = Platform.allCases.map(\.rawValue).joined(separator: " / ")
            return "不正なプラットフォームです: \(value) (指定可能: \(supported))"
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

    public func createLocalization(versionID: String, locale: String, whatsNew: String) async throws -> Localization {
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

    // MARK: - Private

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
