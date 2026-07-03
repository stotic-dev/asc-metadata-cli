import Foundation

/// App Store Connect API のエラーレスポンス
public struct ASCError: Error, CustomStringConvertible, Sendable {
    public struct Detail: Decodable, Sendable {
        public let status: String?
        public let code: String?
        public let title: String?
        public let detail: String?
    }

    public let statusCode: Int
    public let errors: [Detail]

    public var description: String {
        let details = errors
            .map { "- \($0.title ?? "(no title)"): \($0.detail ?? $0.code ?? "(no detail)")" }
            .joined(separator: "\n")
        return "App Store Connect API error (HTTP \(statusCode))\n\(details)"
    }
}

/// App Store Connect API の最小クライアント。
/// MVP ではバージョン作成とリリースノート更新に必要なエンドポイントのみ実装している
public struct ASCClient: Sendable {
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

    private let tokenGenerator: ASCTokenGenerator
    private let baseURL: URL
    private let session: URLSession

    public init(
        tokenGenerator: ASCTokenGenerator,
        baseURL: URL = URL(string: "https://api.appstoreconnect.apple.com")!,
        session: URLSession = .shared
    ) {
        self.tokenGenerator = tokenGenerator
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Apps

    public func findApp(bundleID: String) async throws -> App? {
        struct Attributes: Decodable {
            let name: String?
            let bundleId: String?
        }
        let data = try await send(method: "GET", path: "/v1/apps", queryItems: [
            URLQueryItem(name: "filter[bundleId]", value: bundleID),
        ])
        let list = try JSONDecoder().decode(ResourceList<Attributes>.self, from: data)
        guard let app = list.data.first(where: { $0.attributes.bundleId == bundleID }) else {
            return nil
        }
        return App(id: app.id, name: app.attributes.name)
    }

    // MARK: - App Store Versions

    public func findVersion(appID: String, versionString: String, platform: String) async throws -> Version? {
        let data = try await send(method: "GET", path: "/v1/apps/\(appID)/appStoreVersions", queryItems: [
            URLQueryItem(name: "filter[versionString]", value: versionString),
            URLQueryItem(name: "filter[platform]", value: platform),
        ])
        let list = try JSONDecoder().decode(ResourceList<VersionAttributes>.self, from: data)
        guard let version = list.data.first else { return nil }
        return Version(
            id: version.id,
            versionString: version.attributes.versionString,
            state: version.attributes.appStoreState
        )
    }

    public func createVersion(appID: String, versionString: String, platform: String) async throws -> Version {
        struct Body: Encodable {
            struct DataBody: Encodable {
                let type = "appStoreVersions"
                let attributes: Attributes
                let relationships: Relationships
            }
            struct Attributes: Encodable {
                let platform: String
                let versionString: String
            }
            struct Relationships: Encodable {
                let app: Relationship
            }
            struct Relationship: Encodable {
                let data: RelationshipData
            }
            struct RelationshipData: Encodable {
                let type = "apps"
                let id: String
            }
            let data: DataBody
        }

        let body = Body(data: .init(
            attributes: .init(platform: platform, versionString: versionString),
            relationships: .init(app: .init(data: .init(id: appID)))
        ))
        let data = try await send(method: "POST", path: "/v1/appStoreVersions", body: try JSONEncoder().encode(body))
        let document = try JSONDecoder().decode(ResourceDocument<VersionAttributes>.self, from: data)
        return Version(
            id: document.data.id,
            versionString: document.data.attributes.versionString,
            state: document.data.attributes.appStoreState
        )
    }

    // MARK: - App Store Version Localizations

    public func localizations(versionID: String) async throws -> [Localization] {
        let data = try await send(
            method: "GET",
            path: "/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations",
            queryItems: [URLQueryItem(name: "limit", value: "50")]
        )
        let list = try JSONDecoder().decode(ResourceList<LocalizationAttributes>.self, from: data)
        return list.data.map {
            Localization(id: $0.id, locale: $0.attributes.locale, whatsNew: $0.attributes.whatsNew)
        }
    }

    public func updateLocalization(id: String, whatsNew: String) async throws {
        struct Body: Encodable {
            struct DataBody: Encodable {
                let type = "appStoreVersionLocalizations"
                let id: String
                let attributes: Attributes
            }
            struct Attributes: Encodable {
                let whatsNew: String
            }
            let data: DataBody
        }

        let body = Body(data: .init(id: id, attributes: .init(whatsNew: whatsNew)))
        _ = try await send(
            method: "PATCH",
            path: "/v1/appStoreVersionLocalizations/\(id)",
            body: try JSONEncoder().encode(body)
        )
    }

    public func createLocalization(versionID: String, locale: String, whatsNew: String) async throws -> Localization {
        struct Body: Encodable {
            struct DataBody: Encodable {
                let type = "appStoreVersionLocalizations"
                let attributes: Attributes
                let relationships: Relationships
            }
            struct Attributes: Encodable {
                let locale: String
                let whatsNew: String
            }
            struct Relationships: Encodable {
                let appStoreVersion: Relationship
            }
            struct Relationship: Encodable {
                let data: RelationshipData
            }
            struct RelationshipData: Encodable {
                let type = "appStoreVersions"
                let id: String
            }
            let data: DataBody
        }

        let body = Body(data: .init(
            attributes: .init(locale: locale, whatsNew: whatsNew),
            relationships: .init(appStoreVersion: .init(data: .init(id: versionID)))
        ))
        let data = try await send(
            method: "POST",
            path: "/v1/appStoreVersionLocalizations",
            body: try JSONEncoder().encode(body)
        )
        let document = try JSONDecoder().decode(ResourceDocument<LocalizationAttributes>.self, from: data)
        return Localization(
            id: document.data.id,
            locale: document.data.attributes.locale,
            whatsNew: document.data.attributes.whatsNew
        )
    }

    // MARK: - Private

    private struct ResourceList<Attributes: Decodable>: Decodable {
        let data: [Resource<Attributes>]
    }

    private struct ResourceDocument<Attributes: Decodable>: Decodable {
        let data: Resource<Attributes>
    }

    private struct Resource<Attributes: Decodable>: Decodable {
        let id: String
        let attributes: Attributes
    }

    private struct VersionAttributes: Decodable {
        let versionString: String
        let appStoreState: String?
    }

    private struct LocalizationAttributes: Decodable {
        let locale: String
        let whatsNew: String?
    }

    private struct ErrorResponse: Decodable {
        let errors: [ASCError.Detail]
    }

    private func send(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(try tokenGenerator.makeToken())", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let details = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.errors ?? []
            throw ASCError(statusCode: http.statusCode, errors: details)
        }
        return data
    }
}
