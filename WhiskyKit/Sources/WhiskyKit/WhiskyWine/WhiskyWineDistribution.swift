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
}
