//
//  WhiskyWineInstaller.swift
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
import CryptoKit
import SemanticVersion

public class WhiskyWineInstaller {
    /// The Whisky application folder
    public static let applicationFolder = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appending(path: Bundle.whiskyBundleIdentifier)

    /// The folder of all the libfrary files
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")

    /// URL to the installed `wine` `bin` directory
    public static let binFolder: URL = libraryFolder.appending(path: "Wine").appending(path: "bin")

    public static func isWhiskyWineInstalled() -> Bool {
        return whiskyWineVersion() != nil
    }

    public static func install(from archiveURL: URL) async -> Bool {
        defer {
            try? FileManager.default.removeItem(at: archiveURL)
        }

        if let expectedChecksum = await fetchRuntimeArchiveChecksum() {
            do {
                let actualChecksum = try sha256Hex(for: archiveURL)
                if actualChecksum != expectedChecksum {
                    print("Runtime checksum mismatch. Expected \(expectedChecksum), got \(actualChecksum).")
                    return false
                }
            } catch {
                print("Could not hash runtime archive: \(error)")
                return false
            }
        } else {
            print("Runtime checksum was unavailable. Continuing without checksum verification.")
        }

        do {
            if !FileManager.default.fileExists(atPath: applicationFolder.path) {
                try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
            } else {
                try FileManager.default.removeItem(at: applicationFolder)
                try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
            }

            try Tar.untar(tarBall: archiveURL, toURL: applicationFolder)
            try validateRuntimeLayout()
            return true
        } catch {
            print("Failed to install WhiskyWine: \(error)")
            return false
        }
    }

    public static func uninstall() {
        do {
            try FileManager.default.removeItem(at: libraryFolder)
        } catch {
            print("Failed to uninstall WhiskyWine: \(error)")
        }
    }

    public static func shouldUpdateWhiskyWine() async -> (Bool, SemanticVersion) {
        let localVersion = whiskyWineVersion()

        var remoteVersion: SemanticVersion?

        remoteVersion = await withCheckedContinuation { continuation in
            Task.detached {
                do {
                    let data = try await fetchData(from: WhiskyWineDistribution.versionMetadataURL)
                    let decoder = PropertyListDecoder()
                    let remoteInfo = try decoder.decode(WhiskyWineVersion.self, from: data)
                    continuation.resume(returning: remoteInfo.version)
                } catch {
                    print(error)
                    continuation.resume(returning: nil)
                }
            }
        }

        if let localVersion = localVersion, let remoteVersion = remoteVersion {
            if localVersion < remoteVersion {
                return (true, remoteVersion)
            }
        }

        return (false, SemanticVersion(0, 0, 0))
    }

    private static func fetchRuntimeArchiveChecksum() async -> String? {
        await withCheckedContinuation { continuation in
            Task.detached {
                guard let data = try? await fetchData(from: WhiskyWineDistribution.runtimeArchiveChecksumURL),
                      let checksumBody = String(data: data, encoding: .utf8) else {
                    continuation.resume(returning: nil)
                    return
                }

                let checksum = checksumBody
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                    .first
                    .map(String.init)
                    ?? ""

                let validCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
                if checksum.count == 64,
                   checksum.unicodeScalars.allSatisfy({ validCharacters.contains($0) }) {
                    continuation.resume(returning: checksum.lowercased())
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
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

    private static func sha256Hex(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func validateRuntimeLayout() throws {
        let requiredPaths = [
            libraryFolder.appending(path: "Wine/bin/wine64"),
            libraryFolder.appending(path: "Wine/bin/wineserver"),
            libraryFolder.appending(path: "DXVK/x64"),
            libraryFolder.appending(path: "DXVK/x32"),
            libraryFolder.appending(path: "winetricks"),
            libraryFolder.appending(path: "verbs.txt"),
            libraryFolder.appending(path: "WhiskyWineVersion.plist")
        ]

        let missingPaths = requiredPaths.filter {
            !FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
        }

        guard missingPaths.isEmpty else {
            let pathList = missingPaths
                .map { $0.path(percentEncoded: false) }
                .joined(separator: ", ")
            throw NSError(
                domain: "WhiskyWineInstaller",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Runtime layout validation failed. Missing: \(pathList)"]
            )
        }
    }

    public static func whiskyWineVersion() -> SemanticVersion? {
        do {
            let versionPlist = libraryFolder
                .appending(path: "WhiskyWineVersion")
                .appendingPathExtension("plist")

            let decoder = PropertyListDecoder()
            let data = try Data(contentsOf: versionPlist)
            let info = try decoder.decode(WhiskyWineVersion.self, from: data)
            return info.version
        } catch {
            print(error)
            return nil
        }
    }
}

struct WhiskyWineVersion: Codable {
    var version: SemanticVersion = SemanticVersion(1, 0, 0)

    private enum CodingKeys: String, CodingKey {
        case version
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let versionString = try? container.decode(String.self, forKey: .version),
           let parsedVersion = SemanticVersion(versionString) {
            version = parsedVersion
            return
        }

        version = try container.decode(SemanticVersion.self, forKey: .version)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let versionString = "\(version.major).\(version.minor).\(version.patch)"
        try container.encode(versionString, forKey: .version)
    }
}
