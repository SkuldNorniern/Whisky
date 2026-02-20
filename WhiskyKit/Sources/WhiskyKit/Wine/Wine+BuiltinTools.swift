//
//  Wine+BuiltinTools.swift
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

extension Wine {
    private static func spawnWineTool(name: String, args: [String], bottle: Bottle) throws {
        let outputStream = try Wine.runWineProcess(name: name, args: args, bottle: bottle)

        Task.detached(priority: .utility) {
            for await _ in outputStream { }
        }
    }

    private static func runWineTool(
        name: String,
        candidates: [[String]],
        bottle: Bottle
    ) async throws {
        for args in candidates {
            do {
                try spawnWineTool(name: name, args: args, bottle: bottle)
                return
            } catch {
                continue
            }
        }

        throw NSError(
            domain: "WineBuiltinTools",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Failed to launch \(name)."]
        )
    }

    @discardableResult
    public static func control(bottle: Bottle) async throws -> String {
        try await runWineTool(
            name: "control",
            candidates: [["control"], ["control.exe"], ["start", "control.exe"]],
            bottle: bottle
        )
        return ""
    }

    @discardableResult
    public static func regedit(bottle: Bottle) async throws -> String {
        try await runWineTool(
            name: "regedit",
            candidates: [["regedit"], ["regedit.exe"]],
            bottle: bottle
        )
        return ""
    }

    @discardableResult
    public static func cfg(bottle: Bottle) async throws -> String {
        try await runWineTool(
            name: "winecfg",
            candidates: [["winecfg"], ["winecfg.exe"]],
            bottle: bottle
        )
        return ""
    }
}
