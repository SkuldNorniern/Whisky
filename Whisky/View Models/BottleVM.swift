//
//  BottleVM.swift
//  Whisky
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
import WhiskyKit

// swiftlint:disable:next todo
// TODO: Don't use unchecked!
final class BottleVM: ObservableObject, @unchecked Sendable {
    @MainActor static let shared = BottleVM()

    var bottlesList = BottleData()
    @Published var bottles: [Bottle] = []

    @MainActor
    func loadBottles() {
        bottles = bottlesList.loadBottles()
    }

    func countActive() -> Int {
        return bottles.filter { $0.isAvailable == true }.count
    }

    func createNewBottle(
        bottleName: String,
        winVersion: WinVersion,
        wineRuntime: BottleWineRuntime,
        runtimeDownloadURL: URL?,
        bottleURL: URL
    ) async -> URL? {
        let newBottleDir = bottleURL.appending(path: UUID().uuidString)

        var bottleId: Bottle?
        do {
            try await Self.ensureRuntimeInstalled(runtime: wineRuntime, downloadURL: runtimeDownloadURL)

            try FileManager.default.createDirectory(atPath: newBottleDir.path(percentEncoded: false),
                                                    withIntermediateDirectories: true)
            let bottle = Bottle(bottleUrl: newBottleDir, inFlight: true)
            bottleId = bottle

            await MainActor.run {
                self.bottles.append(bottle)
            }

            bottle.settings.windowsVersion = winVersion
            bottle.settings.name = bottleName
            bottle.settings.wineRuntime = wineRuntime
            try await Wine.changeWinVersion(bottle: bottle, win: winVersion)
            let wineVer = try await Wine.wineVersion(bottle: bottle)
            bottle.settings.wineVersion = SemanticVersion(wineVer) ?? SemanticVersion(0, 0, 0)
            // Add record
            await MainActor.run {
                self.bottlesList.paths.append(newBottleDir)
                self.loadBottles()
            }

            return newBottleDir
        } catch {
            print("Failed to create new bottle: \(error)")
            if let bottle = bottleId {
                await MainActor.run {
                    if let index = self.bottles.firstIndex(of: bottle) {
                        self.bottles.remove(at: index)
                    }
                }
            }

            if FileManager.default.fileExists(atPath: newBottleDir.path(percentEncoded: false)) {
                try? FileManager.default.removeItem(at: newBottleDir)
            }

            return nil
        }
    }

    private static func ensureRuntimeInstalled(runtime: BottleWineRuntime, downloadURL: URL?) async throws {
        guard case .builtin(let version) = runtime,
              !WhiskyWineInstaller.isBuiltinVersionInstalled(version) else {
            return
        }

        guard let downloadURL,
              ["gz", "xz"].contains(downloadURL.pathExtension.lowercased()) else {
            throw NSError(
                domain: "BottleVM",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Selected runtime is not installed and has no archive URL"
                ]
            )
        }

        let archiveURL = try await downloadArchive(from: downloadURL)
        guard await WhiskyWineInstaller.installBuiltinRuntime(version: version, from: archiveURL) else {
            throw NSError(
                domain: "BottleVM",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to install selected runtime"]
            )
        }
    }

    private static func downloadArchive(from url: URL) async throws -> URL {
        let (downloadedURL, _) = try await URLSession.shared.download(from: url)
        let destination = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension(url.pathExtension)

        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.moveItem(at: downloadedURL, to: destination)
        return destination
    }
}
