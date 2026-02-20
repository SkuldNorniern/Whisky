//
//  RustCoreBridge.swift
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
import Darwin

enum RustCoreBridge {
    private typealias ValidatePEFileFunction = @convention(c) (UnsafePointer<CChar>?) -> Bool
    private typealias ExtractPEHeaderFunction = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafeMutablePointer<UInt16>?,
        UnsafeMutablePointer<UInt16>?,
        UnsafeMutablePointer<UInt32>?
    ) -> Bool

    struct RustPEHeaderMetadata: Equatable {
        let machine: UInt16
        let subsystem: UInt16
        let entryPointRVA: UInt32
    }

    private static let validatePEFile: ValidatePEFileFunction? = {
        return RustCoreLoader.resolveSymbol(
            named: ["vodka_pe_validate_file", "whisky_rust_pe_validate_file"],
            as: ValidatePEFileFunction.self
        )
    }()

    private static let extractPEHeader: ExtractPEHeaderFunction? = {
        RustCoreLoader.resolveSymbol(
            named: ["vodka_pe_extract_header", "whisky_rust_pe_extract_header"],
            as: ExtractPEHeaderFunction.self
        )
    }()

    static func validatePortableExecutable(at url: URL) -> Bool? {
        guard let validatePEFile else {
            return nil
        }

        return url.path.withCString { path in
            validatePEFile(path)
        }
    }

    static func extractPortableExecutableMetadata(at url: URL) -> RustPEHeaderMetadata? {
        guard let extractPEHeader else {
            return nil
        }

        var machine: UInt16 = 0
        var subsystem: UInt16 = 0
        var entryPointRVA: UInt32 = 0

        let didExtractMetadata = url.path.withCString { path in
            extractPEHeader(path, &machine, &subsystem, &entryPointRVA)
        }

        guard didExtractMetadata else {
            return nil
        }

        return RustPEHeaderMetadata(
            machine: machine,
            subsystem: subsystem,
            entryPointRVA: entryPointRVA
        )
    }
}

private enum RustCoreLoader {
    private struct RustLibraryHandle: @unchecked Sendable {
        let rawValue: UnsafeMutableRawPointer
    }

    private static let handle: RustLibraryHandle? = {
        for candidatePath in Self.candidateLibraryPaths {
            if let handle = dlopen(candidatePath, RTLD_NOW | RTLD_LOCAL) {
                return RustLibraryHandle(rawValue: handle)
            }
        }

        return nil
    }()

    static func resolveSymbol<T>(named symbolNames: [String], as _: T.Type) -> T? {
        guard let handle else {
            return nil
        }

        for symbolName in symbolNames {
            if let symbol = dlsym(handle.rawValue, symbolName) {
                return unsafeBitCast(symbol, to: T.self)
            }
        }

        return nil
    }

    private static var candidateLibraryPaths: [String] {
        var paths = [String]()

        if let envPath = ProcessInfo.processInfo.environment["WHISKY_RUST_CORE_LIB"], !envPath.isEmpty {
            paths.append(envPath)
        }

        if let bundlePath = Bundle.main.privateFrameworksURL?
            .appending(path: "libwhiskyrustcore.dylib")
            .path(percentEncoded: false) {
            paths.append(bundlePath)
        }

        if let vodkaBundlePath = Bundle.main.privateFrameworksURL?
            .appending(path: "libvodka_core.dylib")
            .path(percentEncoded: false) {
            paths.append(vodkaBundlePath)
        }

        paths.append("libvodka_core.dylib")
        paths.append("libwhiskyrustcore.dylib")
        paths.append("/opt/homebrew/lib/libvodka_core.dylib")
        paths.append("/opt/homebrew/lib/libwhiskyrustcore.dylib")
        paths.append("/usr/local/lib/libvodka_core.dylib")
        paths.append("/usr/local/lib/libwhiskyrustcore.dylib")

        return paths
    }
}
