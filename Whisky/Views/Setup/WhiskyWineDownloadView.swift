//
//  WhiskyWineDownloadView.swift
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

import SwiftUI
import WhiskyKit

struct WhiskyWineDownloadView: View {
    @State private var fractionProgress: Double = 0
    @State private var completedBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var downloadSpeed: Double = 0
    @State private var downloadTask: URLSessionDownloadTask?
    @State private var observation: NSKeyValueObservation?
    @State private var startTime: Date?
    @State private var downloadFailed: Bool = false
    @State private var downloadErrorMessage: String?
    @Binding var tarLocation: URL
    @Binding var path: [SetupStage]
    var runtimeArchiveURL: URL = WhiskyWineDistribution.runtimeArchiveURL
    var body: some View {
        VStack {
            VStack {
                Text("setup.whiskywine.download")
                    .font(.title)
                    .fontWeight(.bold)
                Text("setup.whiskywine.download.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack {
                    if downloadFailed {
                        Image(systemName: "xmark.circle")
                            .resizable()
                            .frame(width: 48, height: 48)
                            .foregroundStyle(.red)
                        if let downloadErrorMessage {
                            Text(downloadErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    } else {
                        ProgressView(value: fractionProgress, total: 1)
                    }
                    HStack {
                        HStack {
                            Text(String(format: String(localized: "setup.whiskywine.progress"),
                                        formatBytes(bytes: completedBytes),
                                        formatBytes(bytes: totalBytes)))
                            + Text(String(" "))
                            + (shouldShowEstimate() ?
                               Text(String(format: String(localized: "setup.whiskywine.eta"),
                                           formatRemainingTime(remainingBytes: totalBytes - completedBytes)))
                               : Text(String()))
                            Spacer()
                        }
                        .font(.subheadline)
                        .monospacedDigit()
                    }
                }
                .padding(.horizontal)
                Spacer()
            }
            Spacer()
        }
        .frame(width: 400, height: 200)
        .onAppear {
            Task {
                if runtimeArchiveURL.isFileURL {
                    await MainActor.run {
                        downloadSpeed = 0
                        completedBytes = 1
                        totalBytes = 1
                        fractionProgress = 1
                    }

                    do {
                        let localArchive = try copyLocalRuntimeArchiveToTemporaryFile(
                            from: runtimeArchiveURL
                        )

                        await MainActor.run {
                            tarLocation = localArchive
                            proceed()
                        }
                    } catch {
                        await MainActor.run {
                            downloadFailed = true
                            downloadErrorMessage = "Failed to load local runtime archive."
                        }
                    }

                    return
                }

                let session = URLSession(configuration: .ephemeral)
                downloadTask = session.downloadTask(with: runtimeArchiveURL) { url, _, error in
                    Task.detached {
                        await MainActor.run {
                            if let error {
                                downloadFailed = true
                                downloadErrorMessage = "Runtime download failed: \(error.localizedDescription)"
                                return
                            }

                            guard let url = url else {
                                downloadFailed = true
                                downloadErrorMessage = "Runtime download failed."
                                return
                            }

                            do {
                                let stableArchive = try copyDownloadedArchiveToTemporaryFile(
                                    from: url,
                                    originalURL: runtimeArchiveURL
                                )
                                tarLocation = stableArchive
                                proceed()
                            } catch {
                                downloadFailed = true
                                downloadErrorMessage = "Failed to prepare runtime archive."
                            }
                        }
                    }
                }
                observation = downloadTask?.observe(\.countOfBytesReceived) { task, _ in
                    Task {
                        await MainActor.run {
                            let currentTime = Date()
                            let elapsedTime = currentTime.timeIntervalSince(startTime ?? currentTime)
                            if completedBytes > 0 {
                                let safeElapsedTime = max(elapsedTime, 0.001)
                                downloadSpeed = Double(completedBytes) / safeElapsedTime
                            }
                            totalBytes = task.countOfBytesExpectedToReceive
                            completedBytes = task.countOfBytesReceived
                            let total = max(totalBytes, 1)
                            fractionProgress = min(max(Double(completedBytes) / Double(total), 0), 1)
                        }
                    }
                }
                startTime = Date()
                downloadTask?.resume()
            }
        }
    }

    func formatBytes(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = true
        return formatter.string(fromByteCount: bytes)
    }

    func shouldShowEstimate() -> Bool {
        let elapsedTime = Date().timeIntervalSince(startTime ?? Date())
        return Int(elapsedTime.rounded()) > 5
            && completedBytes > 0
            && downloadSpeed > 0
            && downloadSpeed.isFinite
    }

    func formatRemainingTime(remainingBytes: Int64) -> String {
        guard shouldShowEstimate(), remainingBytes > 0 else {
            return ""
        }

        let remainingTimeInSeconds = Double(remainingBytes) / downloadSpeed
        guard remainingTimeInSeconds.isFinite, remainingTimeInSeconds > 0 else {
            return ""
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        return formatter.string(from: TimeInterval(remainingTimeInSeconds)) ?? ""
    }

    func proceed() {
        path.append(.whiskyWineInstall)
    }

    func copyLocalRuntimeArchiveToTemporaryFile(from sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let destinationURL = buildTemporaryArchiveURL(using: sourceURL)

        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    func copyDownloadedArchiveToTemporaryFile(from sourceURL: URL, originalURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let destinationURL = buildTemporaryArchiveURL(using: originalURL)

        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    func buildTemporaryArchiveURL(using sourceURL: URL) -> URL {
        let fileManager = FileManager.default
        let lowerPath = sourceURL.lastPathComponent.lowercased()
        let extensionString: String
        if lowerPath.hasSuffix(".tar.xz") {
            extensionString = "tar.xz"
        } else {
            extensionString = "tar.gz"
        }
        return fileManager.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension(extensionString)
    }
}
