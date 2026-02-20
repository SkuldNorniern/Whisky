//
//  Wine.swift
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
import os.log

public class Wine {
    private struct RuntimeBinaries {
        let wine: URL
        let wineserver: URL
        let binFolder: URL
    }

    /// URL to the installed `DXVK` folder
    private static let dxvkFolder: URL = WhiskyWineInstaller.toolsFolder.appending(path: "DXVK")
    /// Path to the `wine64` binary
    public static let wineBinary: URL = WhiskyWineInstaller.binFolder.appending(path: "wine64")
    /// Parth to the `wineserver` binary
    private static let wineserverBinary: URL = WhiskyWineInstaller.binFolder.appending(path: "wineserver")

    private static func resolvedWineBinary(in binFolder: URL) -> URL {
        let wine64 = binFolder.appending(path: "wine64")
        if FileManager.default.fileExists(atPath: wine64.path(percentEncoded: false)) {
            return wine64
        }

        let wine = binFolder.appending(path: "wine")
        if FileManager.default.fileExists(atPath: wine.path(percentEncoded: false)) {
            return wine
        }

        return wineBinary
    }

    private static func resolvedWineserverBinary(in binFolder: URL) -> URL {
        let wineserver = binFolder.appending(path: "wineserver")
        if FileManager.default.fileExists(atPath: wineserver.path(percentEncoded: false)) {
            return wineserver
        }

        return wineserverBinary
    }

    private static func runtimeBinaries(for bottle: Bottle?) throws -> RuntimeBinaries {
        guard let bottle else {
            return RuntimeBinaries(
                wine: wineBinary,
                wineserver: wineserverBinary,
                binFolder: WhiskyWineInstaller.binFolder
            )
        }

        let binFolder = try WhiskyWineInstaller.resolveBinFolder(for: bottle.settings.wineRuntime)
        let wine = resolvedWineBinary(in: binFolder)
        let wineserver = resolvedWineserverBinary(in: binFolder)
        return RuntimeBinaries(wine: wine, wineserver: wineserver, binFolder: binFolder)
    }

    public static func runtimeBinFolder(for bottle: Bottle) -> URL {
        return (try? runtimeBinaries(for: bottle).binFolder) ?? WhiskyWineInstaller.binFolder
    }

    public static func runtimeWineCommand(for bottle: Bottle) -> String {
        let resolved = (try? runtimeBinaries(for: bottle).wine) ?? wineBinary
        return resolved.lastPathComponent
    }

    /// Run a process on a executable file given by the `executableURL`
    private static func runProcess(
        name: String? = nil, args: [String], environment: [String: String], executableURL: URL, directory: URL? = nil,
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = args
        process.currentDirectoryURL = directory ?? executableURL.deletingLastPathComponent()
        process.environment = environment
        process.qualityOfService = .userInitiated

        return try process.runStream(
            name: name ?? args.joined(separator: " "), fileHandle: fileHandle
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    private static func runWineProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        executableURL: URL,
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment, executableURL: executableURL,
            fileHandle: fileHandle
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    private static func runWineserverProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        executableURL: URL,
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment, executableURL: executableURL,
            fileHandle: fileHandle
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    public static func runWineProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        let binaries = try runtimeBinaries(for: bottle)
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicaitonInfo()
        fileHandle.writeInfo(for: bottle)

        return try runWineProcess(
            name: name, args: args,
            environment: constructWineEnvironment(for: bottle, environment: environment),
            executableURL: binaries.wine,
            fileHandle: fileHandle
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    public static func runWineserverProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        let binaries = try runtimeBinaries(for: bottle)
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicaitonInfo()
        fileHandle.writeInfo(for: bottle)

        return try runWineserverProcess(
            name: name, args: args,
            environment: constructWineServerEnvironment(for: bottle, environment: environment),
            executableURL: binaries.wineserver,
            fileHandle: fileHandle
        )
    }

    /// Execute a `wine start /unix {url}` command returning the output result
    public static func runProgram(
        at url: URL, args: [String] = [], bottle: Bottle, environment: [String: String] = [:]
    ) async throws {
        if bottle.settings.dxvk {
            try enableDXVK(bottle: bottle)
        }

        for await _ in try Self.runWineProcess(
            name: url.lastPathComponent,
            args: ["start", "/unix", url.path(percentEncoded: false)] + args,
            bottle: bottle, environment: environment
        ) { }
    }

    public static func generateRunCommand(
        at url: URL, bottle: Bottle, args: String, environment: [String: String]
    ) -> String {
        let resolvedWineBinary = (try? runtimeBinaries(for: bottle).wine) ?? wineBinary
        var wineCmd = "\(resolvedWineBinary.esc) start /unix \(url.esc) \(args)"
        let env = constructWineEnvironment(for: bottle, environment: environment)
        for environment in env {
            wineCmd = "\(environment.key)=\"\(environment.value)\" " + wineCmd
        }

        return wineCmd
    }

    public static func generateTerminalEnvironmentCommand(bottle: Bottle) -> String {
        let resolvedBinFolder = runtimeBinFolder(for: bottle)
        let wineCommand = runtimeWineCommand(for: bottle)
        var cmd = """
        export PATH=\"\(resolvedBinFolder.path):$PATH\"
        export WINE=\"\(wineCommand)\"
        alias wine=\"\(wineCommand)\"
        alias winecfg=\"\(wineCommand) winecfg.exe\"
        alias msiexec=\"\(wineCommand) msiexec\"
        alias regedit=\"\(wineCommand) regedit.exe\"
        alias regsvr32=\"\(wineCommand) regsvr32\"
        alias wineboot=\"\(wineCommand) wineboot\"
        alias wineconsole=\"\(wineCommand) wineconsole\"
        alias winedbg=\"\(wineCommand) winedbg\"
        alias winefile=\"\(wineCommand) winefile\"
        alias winepath=\"\(wineCommand) winepath\"
        """

        let env = constructWineEnvironment(for: bottle, environment: constructWineEnvironment(for: bottle))
        for environment in env {
            cmd += "\nexport \(environment.key)=\"\(environment.value)\""
        }

        return cmd
    }

    /// Run a `wineserver` command with the given arguments and return the output result
    private static func runWineserver(_ args: [String], bottle: Bottle) async throws -> String {
        var result: [ProcessOutput] = []

        for await output in try Self.runWineserverProcess(args: args, bottle: bottle, environment: [:]) {
            result.append(output)
        }

        return result.compactMap { output -> String? in
            switch output {
            case .started, .terminated:
                return nil
            case .message(let message), .error(let message):
                return message
            }
        }.joined()
    }

    @discardableResult
    /// Run a `wine` command with the given arguments and return the output result
    public static func runWine(
        _ args: [String], bottle: Bottle?, environment: [String: String] = [:]
    ) async throws -> String {
        var result: [String] = []
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicaitonInfo()
        var environment = environment
        let binaries = try runtimeBinaries(for: bottle)

        if let bottle = bottle {
            fileHandle.writeInfo(for: bottle)
            environment = constructWineEnvironment(for: bottle, environment: environment)
        }

        for await output in try runWineProcess(
            args: args,
            environment: environment,
            executableURL: binaries.wine,
            fileHandle: fileHandle
        ) {
            switch output {
            case .started, .terminated:
                break
            case .message(let message), .error(let message):
                result.append(message)
            }
        }

        return result.joined()
    }

    public static func wineVersion(bottle: Bottle? = nil) async throws -> String {
        var output = try await runWine(["--version"], bottle: bottle)
        output.replace("wine-", with: "")

        // Deal with WineCX version names
        if let index = output.firstIndex(where: { $0.isWhitespace }) {
            return String(output.prefix(upTo: index))
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    public static func runBatchFile(url: URL, bottle: Bottle) async throws -> String {
        return try await runWine(["cmd", "/c", url.path(percentEncoded: false)], bottle: bottle)
    }

    public static func killBottle(bottle: Bottle) throws {
        Task.detached(priority: .userInitiated) {
            try await runWineserver(["-k"], bottle: bottle)
        }
    }

    public static func enableDXVK(bottle: Bottle) throws {
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "system32"),
            withContentsIn: Wine.dxvkFolder.appending(path: "x64")
        )
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "syswow64"),
            withContentsIn: Wine.dxvkFolder.appending(path: "x32")
        )
    }

    /// Construct an environment merging the bottle values with the given values
    private static func constructWineEnvironment(
        for bottle: Bottle, environment: [String: String] = [:]
    ) -> [String: String] {
        var result: [String: String] = [
            "WINEPREFIX": bottle.url.path,
            "WINEDEBUG": "fixme-all",
            "GST_DEBUG": "1"
        ]
        bottle.settings.environmentVariables(wineEnv: &result)
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }

    /// Construct an environment merging the bottle values with the given values
    private static func constructWineServerEnvironment(
        for bottle: Bottle, environment: [String: String] = [:]
    ) -> [String: String] {
        var result: [String: String] = [
            "WINEPREFIX": bottle.url.path,
            "WINEDEBUG": "fixme-all",
            "GST_DEBUG": "1"
        ]
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }
}
