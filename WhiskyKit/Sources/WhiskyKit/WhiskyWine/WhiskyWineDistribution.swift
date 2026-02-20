//
//  WhiskyWineDistribution.swift
//  WhiskyKit
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import SemanticVersion

public enum WhiskyWineDistribution {
    public static let defaultWineVersion = SemanticVersion(9, 0, 0)
    private static let defaultBaseURLString = "https://data.getwhisky.app/Wine/"

    private static var configuredLocalFeedURL: URL? {
        let environment = ProcessInfo.processInfo.environment
        guard let localFeedPath = environment["WHISKY_WINE_LOCAL_FEED_DIR"], !localFeedPath.isEmpty else {
            return nil
        }

        let pathURL = URL(fileURLWithPath: localFeedPath, isDirectory: true)
        return pathURL.path.hasSuffix("/") ? pathURL : pathURL.appending(path: "")
    }

    private static var configuredRemoteBaseURLString: String {
        let environment = ProcessInfo.processInfo.environment
        guard let overrideBaseURL = environment["WHISKY_WINE_BASE_URL"], !overrideBaseURL.isEmpty else {
            return defaultBaseURLString
        }

        return overrideBaseURL.hasSuffix("/") ? overrideBaseURL : "\(overrideBaseURL)/"
    }

    public static var baseURL: URL {
        if let localFeedURL = configuredLocalFeedURL {
            return localFeedURL
        }

        guard let url = URL(string: configuredRemoteBaseURLString) else {
            preconditionFailure("Invalid Wine base URL")
        }

        return url
    }

    public static let runtimeArchiveURL = baseURL.appending(path: "Libraries.tar.gz")
    public static let runtimeArchiveChecksumURL = baseURL.appending(path: "Libraries.tar.gz.sha256")
    public static let versionMetadataURL = baseURL.appending(path: "WhiskyWineVersion.plist")

    public enum RuntimeSource: String, Sendable {
        case whiskyOfficial = "Whisky Official"
        case wineHQOfficial = "Wine Official"
    }

    public struct RuntimeCatalogEntry: Sendable, Hashable {
        public let source: RuntimeSource
        public let version: SemanticVersion
        public let url: URL

        public init(source: RuntimeSource, version: SemanticVersion, url: URL) {
            self.source = source
            self.version = version
            self.url = url
        }
    }

    // swiftlint:disable nesting
    private struct GitHubReleaseAsset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let htmlURL: URL
        let assets: [GitHubReleaseAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft
            case prerelease
            case htmlURL = "html_url"
            case assets
        }
    }
    // swiftlint:enable nesting

    public static func fetchOfficialRuntimeCatalog() async -> [RuntimeCatalogEntry] {
        await withTaskGroup(of: RuntimeCatalogEntry?.self) { group in
            group.addTask { await fetchWineHQOfficialRelease() }
            group.addTask { await fetchWineOfficialGitHubRelease(forVersion: SemanticVersion(8, 0, 1)) }
            group.addTask { await fetchWineOfficialGitHubRelease(forVersion: SemanticVersion(9, 21, 0)) }
            group.addTask { await fetchWineOfficialGitHubRelease(forVersion: SemanticVersion(11, 2, 0)) }

            var entries: Set<RuntimeCatalogEntry> = []
            for await entry in group {
                if let entry {
                    entries.insert(entry)
                }
            }

            return Array(entries).sorted { lhs, rhs in
                if lhs.source == rhs.source {
                    return lhs.version > rhs.version
                }
                return lhs.source.rawValue < rhs.source.rawValue
            }
        }
    }

    public static func fetchWhiskyOfficialRuntime() async -> RuntimeCatalogEntry? {
        do {
            let data = try await fetchData(from: versionMetadataURL)
            let decoder = PropertyListDecoder()
            let remoteInfo = try decoder.decode(WhiskyWineVersion.self, from: data)
            return RuntimeCatalogEntry(
                source: .whiskyOfficial,
                version: remoteInfo.version,
                url: runtimeArchiveURL
            )
        } catch {
            return nil
        }
    }

    public static func fetchWineHQOfficialRelease() async -> RuntimeCatalogEntry? {
        guard let tagsURL = URL(
            string: "https://gitlab.winehq.org/api/v4/projects/wine%2Fwine/repository/tags?per_page=1"
        ) else {
            return nil
        }

        struct WineHQTag: Decodable {
            let name: String
        }

        do {
            let data = try await fetchData(from: tagsURL)
            let tags = try JSONDecoder().decode([WineHQTag].self, from: data)
            guard let name = tags.first?.name else { return nil }

            let normalizedName = normalizedVersionTag(from: name)
            guard let version = SemanticVersion(normalizedName) else { return nil }

            let majorPath = "\(version.major).x"
            guard let releaseURL = URL(
                string: "https://dl.winehq.org/wine/source/\(majorPath)/wine-\(normalizedName).tar.xz"
            ) else {
                return nil
            }

            return RuntimeCatalogEntry(
                source: .wineHQOfficial,
                version: version,
                url: releaseURL
            )
        } catch {
            return nil
        }
    }

    public static func fetchWineOfficialGitHubRelease(forMajor major: Int) async -> RuntimeCatalogEntry? {
        guard let releasesURL = URL(
            string: "https://api.github.com/repos/Gcenx/macOS_Wine_builds/releases?per_page=100"
        ) else {
            return nil
        }

        do {
            let data = try await fetchData(from: releasesURL)
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)

            let candidates: [(version: SemanticVersion, url: URL)] = releases.compactMap { release in
                guard !release.draft, !release.prerelease else { return nil }
                let normalized = normalizedVersionTag(from: release.tagName)
                guard let version = SemanticVersion(normalized), version.major == major else { return nil }

                guard let assetURL = preferredAssetURL(from: release.assets) else {
                    return nil
                }
                return (version, assetURL)
            }

            guard let latest = candidates.sorted(by: { $0.version > $1.version }).first else {
                return nil
            }

            return RuntimeCatalogEntry(source: .wineHQOfficial, version: latest.version, url: latest.url)
        } catch {
            return nil
        }
    }

    public static func fetchWineOfficialGitHubRelease(
        forVersion targetVersion: SemanticVersion
    ) async -> RuntimeCatalogEntry? {
        guard let releasesURL = URL(
            string: "https://api.github.com/repos/Gcenx/macOS_Wine_builds/releases?per_page=100"
        ) else {
            return nil
        }

        do {
            let data = try await fetchData(from: releasesURL)
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)

            let candidates: [(version: SemanticVersion, url: URL)] = releases.compactMap { release in
                guard !release.draft, !release.prerelease else { return nil }
                let normalized = normalizedVersionTag(from: release.tagName)
                guard let version = SemanticVersion(normalized) else { return nil }
                guard let assetURL = preferredAssetURL(from: release.assets) else { return nil }
                return (version, assetURL)
            }

            let sameMajor = candidates.filter { $0.version.major == targetVersion.major }
            let exact = sameMajor.first(where: { $0.version == targetVersion })
            let nearestLowerOrEqual = sameMajor
                .filter { $0.version <= targetVersion }
                .sorted(by: { $0.version > $1.version })
                .first
            let nearestMajor = sameMajor.sorted(by: { $0.version > $1.version }).first

            guard let selected = exact ?? nearestLowerOrEqual ?? nearestMajor else {
                return nil
            }

            return RuntimeCatalogEntry(source: .wineHQOfficial, version: selected.version, url: selected.url)
        } catch {
            return nil
        }
    }

    private static func preferredAssetURL(from assets: [GitHubReleaseAsset]) -> URL? {
        let prioritySubstrings = ["wine-stable", "wine-staging", "wine-devel"]
        for priority in prioritySubstrings {
            if let url = assets.first(where: { $0.name.contains(priority) && $0.name.hasSuffix(".tar.xz") })?
                .browserDownloadURL {
                return url
            }
        }

        return assets.first(where: { $0.name.hasSuffix(".tar.xz") })?.browserDownloadURL
    }

    private static func fetchData(from url: URL) async throws -> Data {
        if url.isFileURL {
            return try Data(contentsOf: url)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = URLRequest(url: url)
            URLSession(configuration: .ephemeral).dataTask(with: request) { data, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }

                continuation.resume(returning: data)
            }.resume()
        }
    }

    private static func normalizedVersionTag(from value: String) -> String {
        VodkaBridge.normalizeWineTag(value)
            ?? value.replacingOccurrences(of: "wine-", with: "").replacingOccurrences(of: "v", with: "")
    }
}
