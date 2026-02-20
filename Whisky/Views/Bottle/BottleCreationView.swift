//
//  BottleCreationView.swift
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
import SemanticVersion

private struct CreateRuntimePreset: Hashable {
    let label: String
    let source: String
    let selectionVersion: SemanticVersion?
    let majorTrack: Int?
    let url: URL
}

struct BottleCreationView: View {
    private static let removedRuntimeVersions: Set<SemanticVersion> = [
        SemanticVersion(9, 0, 0),
        SemanticVersion(11, 2, 1)
    ]

    private static let runtimePresets: [CreateRuntimePreset] = [
        ("7.7", "Whisky Official", SemanticVersion(7, 7, 0), nil,
         "https://data.getwhisky.app/Wine/Libraries.tar.gz"),
        ("7.x", "Wine Official", nil, 7, "https://github.com/Gcenx/macOS_Wine_builds/releases"),
        ("8.x", "Wine Official", nil, 8, "https://github.com/Gcenx/macOS_Wine_builds/releases"),
        ("9.22", "Wine Official", SemanticVersion(9, 22, 0), nil,
         "https://github.com/Gcenx/macOS_Wine_builds/releases/download/9.22/wine-devel-9.22-osx64.tar.xz"),
        ("11.2", "Wine Official", SemanticVersion(11, 2, 0), nil,
         "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.2/wine-devel-11.2-osx64.tar.xz")
    ].compactMap { label, source, version, majorTrack, urlString in
        guard let url = URL(string: urlString) else { return nil }
        return CreateRuntimePreset(
            label: label,
            source: source,
            selectionVersion: version,
            majorTrack: majorTrack,
            url: url
        )
    }

    @Binding var newlyCreatedBottleURL: URL?

    @State private var newBottleName: String = ""
    @State private var newBottleVersion: WinVersion = .win10
    @State private var newBottleURL: URL = UserDefaults.standard.url(forKey: "defaultBottleLocation")
                                           ?? BottleData.defaultBottleDir
    @State private var nameValid: Bool = false
    @State private var builtinRuntimeVersions: [SemanticVersion] = []
    @State private var selectedBuiltinRuntimeVersion: SemanticVersion = SemanticVersion(7, 7, 0)
    @State private var officialRuntimeCatalog: [WhiskyWineDistribution.RuntimeCatalogEntry] = []

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("create.name", text: $newBottleName)
                    .onChange(of: newBottleName) { _, name in
                        nameValid = !name.isEmpty
                    }

                Picker("create.win", selection: $newBottleVersion) {
                    ForEach(WinVersion.allCases.reversed(), id: \.self) {
                        Text($0.pretty())
                    }
                }

                Picker("Wine Runtime", selection: $selectedBuiltinRuntimeVersion) {
                    ForEach(builtinRuntimeVersions, id: \.self) { version in
                        Text(runtimeDisplayName(for: version)).tag(version)
                    }
                }

                HStack {
                    Text("Runtime Source")
                    Spacer()
                    Text(selectedRuntimeSource(for: selectedBuiltinRuntimeVersion))
                        .foregroundStyle(.secondary)
                }

                if let selectedURL = selectedRuntimeURL(for: selectedBuiltinRuntimeVersion) {
                    HStack {
                        Text("Selected URL")
                        Spacer()
                        Link(selectedURL.absoluteString, destination: selectedURL)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                ActionView(
                    text: "create.path",
                    subtitle: newBottleURL.prettyPath(),
                    actionName: "create.browse"
                ) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = true
                    panel.directoryURL = BottleData.containerDir
                    panel.begin { result in
                        if result == .OK, let url = panel.urls.first {
                            newBottleURL = url
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("create.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("create.cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("create.create") {
                        submit()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!nameValid)
                }
            }
            .onSubmit {
                submit()
            }
            .onAppear {
                loadRuntimeConfiguration()
                loadOfficialRuntimeCatalog()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: ViewWidth.small)
    }

    func submit() {
        let runtime = BottleWineRuntime.builtin(version: selectedBuiltinRuntimeVersion)
        newlyCreatedBottleURL = BottleVM.shared.createNewBottle(bottleName: newBottleName,
                                                                 winVersion: newBottleVersion,
                                                                 wineRuntime: runtime,
                                                                 runtimeDownloadURL: selectedRuntimeURL(
                                                                    for: selectedBuiltinRuntimeVersion
                                                                 ),
                                                                 bottleURL: newBottleURL)
        dismiss()
    }

    func loadRuntimeConfiguration() {
        var available = WhiskyWineInstaller.availableBuiltinWineVersions()
            .filter { !Self.removedRuntimeVersions.contains($0) }

        for preset in Self.runtimePresets {
            guard let presetVersion = resolvedPresetVersion(for: preset),
                  !Self.removedRuntimeVersions.contains(presetVersion) else { continue }
            if !available.contains(presetVersion) {
                available.append(presetVersion)
            }
        }

        builtinRuntimeVersions = available.sorted(by: >)

        let defaultVersion = SemanticVersion(7, 7, 0)
        if builtinRuntimeVersions.contains(defaultVersion) {
            selectedBuiltinRuntimeVersion = defaultVersion
        } else if let first = builtinRuntimeVersions.first {
            selectedBuiltinRuntimeVersion = first
        }
    }

    func loadOfficialRuntimeCatalog() {
        Task(priority: .utility) {
            let catalog = await WhiskyWineDistribution.fetchOfficialRuntimeCatalog()
            await MainActor.run {
                officialRuntimeCatalog = catalog
                loadRuntimeConfiguration()
            }
        }
    }

    func runtimeDisplayName(for version: SemanticVersion) -> String {
        if let preset = preset(for: version) {
            let resolvedVersion = resolvedPresetVersion(for: preset) ?? version
            return "\(resolvedVersion.major).\(resolvedVersion.minor).\(resolvedVersion.patch) (\(preset.source))"
        }

        let versionString = "\(version.major).\(version.minor).\(version.patch)"
        let source = officialCatalogEntry(for: version)?.source.rawValue
        if let source {
            return "\(versionString) (\(source))"
        }
        return versionString
    }

    func selectedRuntimeSource(for version: SemanticVersion) -> String {
        if let preset = preset(for: version) {
            return preset.source
        }
        return officialCatalogEntry(for: version)?.source.rawValue ?? "Unknown"
    }

    func selectedRuntimeURL(for version: SemanticVersion) -> URL? {
        if let preset = preset(for: version) {
            return resolvedPresetURL(for: preset)
        }
        return officialCatalogEntry(for: version)?.url
    }

    func officialCatalogEntry(for version: SemanticVersion) -> WhiskyWineDistribution.RuntimeCatalogEntry? {
        officialRuntimeCatalog.first(where: { $0.version == version })
    }

    private func preset(for version: SemanticVersion) -> CreateRuntimePreset? {
        Self.runtimePresets.first(where: { resolvedPresetVersion(for: $0) == version })
    }

    private func resolvedPresetVersion(for preset: CreateRuntimePreset) -> SemanticVersion? {
        if let fixedVersion = preset.selectionVersion {
            return fixedVersion
        }

        guard let majorTrack = preset.majorTrack else { return nil }
        return officialRuntimeCatalog
            .filter { $0.source == .wineHQOfficial && $0.version.major == majorTrack }
            .map(\.version)
            .sorted(by: >)
            .first
    }

    private func resolvedPresetURL(for preset: CreateRuntimePreset) -> URL? {
        if preset.selectionVersion != nil, preset.source == "Wine Official" {
            return preset.url
        }

        if preset.source == "Wine Official" {
            guard let majorTrack = preset.majorTrack else { return nil }
            return officialRuntimeCatalog
                .filter { $0.source == .wineHQOfficial && $0.version.major == majorTrack }
                .sorted(by: { $0.version > $1.version })
                .first?
                .url
        }

        return preset.url
    }
}

#Preview {
    BottleCreationView(newlyCreatedBottleURL: .constant(nil))
}
