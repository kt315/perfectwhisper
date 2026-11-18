import Foundation

/// Information about an available release.
struct UpdateRelease: Equatable, Sendable {
    let version: String
    let notes: String
    let downloadURL: URL?
    let pageURL: URL?
}

enum UpdateError: LocalizedError {
    case notConfigured
    case noReleases
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return L10n.t("No GitLab project configured for updates")
        case .noReleases: return L10n.t("The project has no releases")
        case .badResponse: return L10n.t("Invalid server response")
        }
    }
}

/// Version comparison for strings like `1.2.3` / `v1.2.3`.
enum VersionCompare {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = components(candidate)
        let rhs = components(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    static func normalized(_ version: String) -> String {
        components(version).map(String.init).joined(separator: ".")
    }

    private static func components(_ version: String) -> [Int] {
        var value = version.trimmingCharacters(in: .whitespaces)
        if value.first == "v" || value.first == "V" { value.removeFirst() }
        let core = value.split(separator: "-").first.map(String.init) ?? value
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }
}

// MARK: - GitLab

struct GitLabRelease: Decodable, Sendable {
    let tagName: String
    let name: String?
    let description: String?
    let assets: Assets?
    let links: Links?

    struct Assets: Decodable, Sendable {
        let links: [AssetLink]
    }

    struct AssetLink: Decodable, Sendable {
        let name: String
        let url: String
        let directAssetURL: String?

        enum CodingKeys: String, CodingKey {
            case name, url
            case directAssetURL = "direct_asset_url"
        }
    }

    struct Links: Decodable, Sendable {
        let webURL: String?

        enum CodingKeys: String, CodingKey {
            case webURL = "self"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, description, assets
        case links = "_links"
    }

    var version: String { VersionCompare.normalized(tagName) }

    func resolvedDownloadURL() -> URL? {
        let dmg = assets?.links.first {
            $0.name.lowercased().hasSuffix(".dmg") || $0.url.lowercased().hasSuffix(".dmg")
        }
        if let dmg, let url = URL(string: dmg.directAssetURL ?? dmg.url) { return url }
        if let web = links?.webURL { return URL(string: web) }
        return nil
    }

    func resolvedPageURL(project: String) -> URL? {
        if let web = links?.webURL { return URL(string: web) }
        return URL(string: "https://gitlab.com/\(project)/-/releases/\(tagName)")
    }
}

enum GitLabUpdater {
    static let host = "https://gitlab.com"
    static let api = "\(host)/api/v4"

    static func latestRelease(projectPath: String) async throws -> UpdateRelease {
        guard !projectPath.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw UpdateError.notConfigured
        }

        let encoded = projectPath.replacingOccurrences(of: "/", with: "%2F")
        guard let url = URL(string: "\(api)/projects/\(encoded)/releases?per_page=20") else {
            throw UpdateError.badResponse
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError.badResponse
        }

        let releases = try JSONDecoder().decode([GitLabRelease].self, from: data)
        guard let newest = releases.max(by: {
            VersionCompare.isNewer($1.version, than: $0.version)
        }) else {
            throw UpdateError.noReleases
        }

        return UpdateRelease(
            version: newest.version,
            notes: newest.description ?? newest.name ?? "",
            downloadURL: newest.resolvedDownloadURL(),
            pageURL: newest.resolvedPageURL(project: projectPath)
        )
    }
}
