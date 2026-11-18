import Foundation

struct GitHubRelease: Decodable, Sendable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: String?
    let assets: [Asset]

    struct Asset: Decodable, Sendable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, assets
        case htmlURL = "html_url"
    }

    var version: String { VersionCompare.normalized(tagName) }

    func resolvedDownloadURL() -> URL? {
        let dmg = assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        if let dmg { return URL(string: dmg.browserDownloadURL) }
        if let htmlURL { return URL(string: htmlURL) }
        return nil
    }
}

enum GitHubUpdater {
    static func latestRelease(projectPath: String) async throws -> UpdateRelease {
        guard !projectPath.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw UpdateError.notConfigured
        }
        guard let url = URL(string: "https://api.github.com/repos/\(projectPath)/releases/latest") else {
            throw UpdateError.badResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PerfectWhisper", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError.badResponse
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        return UpdateRelease(
            version: release.version,
            notes: release.body ?? release.name ?? "",
            downloadURL: release.resolvedDownloadURL(),
            pageURL: release.htmlURL.flatMap(URL.init(string:))
        )
    }
}
