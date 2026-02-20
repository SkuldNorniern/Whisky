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

private struct CreateRuntimeOption: Hashable {
    let id: String
    let version: SemanticVersion
    let source: String
    let url: URL?
}

// swiftlint:disable type_body_length
struct BottleCreationView: View {
    private static let excludedRuntimeVersions: Set<SemanticVersion> = [
        SemanticVersion(11, 2, 1)
    ]

    private static let runtimePresets: [CreateRuntimePreset] = [
        ("7.7", "Whisky Official", SemanticVersion(7, 7, 0), nil,
         "https://data.getwhisky.app/Wine/Libraries.tar.gz"),
        ("8.0.1", "Wine Official", SemanticVersion(8, 0, 1), nil,
         "https://github.com/Gcenx/macOS_Wine_builds/releases/download/8.0.1/wine-stable-8.0.1-osx64.tar.xz"),
        ("9.21", "Wine Official", SemanticVersion(9, 21, 0), nil,
         "https://github.com/Gcenx/macOS_Wine_builds/releases/download/9.21/wine-devel-9.21-osx64.tar.xz"),
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
    @State private var creatingBottle: Bool = false
    @State private var creatingStatusMessage: String?
    @State private var createErrorMessage: String?
    @State private var builtinRuntimeOptions: [CreateRuntimeOption] = []
    @State private var selectedBuiltinRuntimeID: String = ""
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

                Picker("Wine Runtime", selection: $selectedBuiltinRuntimeID) {
                    ForEach(builtinRuntimeOptions, id: \.id) { option in
                        Text(runtimeDisplayName(for: option)).tag(option.id)
                    }
                }

                HStack {
                    Text("Runtime Source")
                    Spacer()
                    Text(selectedBuiltinRuntimeSource)
                        .foregroundStyle(.secondary)
                }

                if let selectedURL = selectedBuiltinRuntimeURL {
                    HStack {
                        Text("Selected URL")
                        Spacer()
                        Link(selectedURL.absoluteString, destination: selectedURL)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                if creatingBottle {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(creatingStatusMessage ?? "Creating bottle...")
                            .foregroundStyle(.secondary)
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
                    .disabled(!nameValid || creatingBottle)
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
        .alert("Create Bottle Failed", isPresented: Binding(
            get: { createErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    createErrorMessage = nil
                }
            }
        )) {
            Button("OK") {
                createErrorMessage = nil
            }
        } message: {
            Text(createErrorMessage ?? "Unknown error")
        }
    }

    func submit() {
        guard !creatingBottle else { return }
        creatingBottle = true
        if !WhiskyWineInstaller.isBuiltinVersionInstalled(selectedBuiltinRuntimeVersion) {
            creatingStatusMessage = "Installing selected runtime..."
        } else {
            creatingStatusMessage = "Creating bottle..."
        }

        let runtime = BottleWineRuntime.builtin(version: selectedBuiltinRuntimeVersion)
        Task {
            let createdURL = await BottleVM.shared.createNewBottle(
                bottleName: newBottleName,
                winVersion: newBottleVersion,
                wineRuntime: runtime,
                runtimeDownloadURL: selectedBuiltinRuntimeURL,
                bottleURL: newBottleURL
            )

            await MainActor.run {
                creatingBottle = false
                creatingStatusMessage = nil
                if let createdURL {
                    newlyCreatedBottleURL = createdURL
                    dismiss()
                } else {
                    createErrorMessage = "Failed to create bottle. Runtime install or initialization failed."
                }
            }
        }
    }

    func loadRuntimeConfiguration() {
        var available = WhiskyWineInstaller.availableBuiltinWineVersions()
            .filter { !Self.excludedRuntimeVersions.contains($0) }

        for preset in Self.runtimePresets {
            guard let presetVersion = resolvedPresetVersion(for: preset) else { continue }
            guard !Self.excludedRuntimeVersions.contains(presetVersion) else { continue }
            if !available.contains(presetVersion) {
                available.append(presetVersion)
            }
        }

        builtinRuntimeOptions = buildRuntimeOptions(from: available)

        if let whiskyDefault = builtinRuntimeOptions.first(where: {
            $0.version == SemanticVersion(7, 7, 0) && $0.source == "Whisky Official"
        }) {
            selectedBuiltinRuntimeID = whiskyDefault.id
        } else if let first = builtinRuntimeOptions.first {
            selectedBuiltinRuntimeID = first.id
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

    private func runtimeDisplayName(for option: CreateRuntimeOption) -> String {
        let version = option.version
        return "\(version.major).\(version.minor).\(version.patch) (\(option.source))"
    }

    var selectedBuiltinRuntimeVersion: SemanticVersion {
        builtinRuntimeOptions.first(where: { $0.id == selectedBuiltinRuntimeID })?.version
            ?? SemanticVersion(7, 7, 0)
    }

    var selectedBuiltinRuntimeSource: String {
        builtinRuntimeOptions.first(where: { $0.id == selectedBuiltinRuntimeID })?.source
            ?? "Unknown"
    }

    var selectedBuiltinRuntimeURL: URL? {
        builtinRuntimeOptions.first(where: { $0.id == selectedBuiltinRuntimeID })?.url
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

    private func buildRuntimeOptions(from versions: [SemanticVersion]) -> [CreateRuntimeOption] {
        var options: [CreateRuntimeOption] = []

        for preset in Self.runtimePresets {
            guard let version = resolvedPresetVersion(for: preset), versions.contains(version) else { continue }
            options.append(
                CreateRuntimeOption(
                    id: "preset:\(preset.source):\(preset.label)",
                    version: version,
                    source: preset.source,
                    url: resolvedPresetURL(for: preset)
                )
            )
        }

        let knownVersions = Set(options.map(\.version))
        let unknownVersions = versions.filter { !knownVersions.contains($0) }.sorted(by: >)
        for version in unknownVersions {
            options.append(
                CreateRuntimeOption(
                    id: "version:\(version.major).\(version.minor).\(version.patch)",
                    version: version,
                    source: officialCatalogEntry(for: version)?.source.rawValue ?? "Installed",
                    url: officialCatalogEntry(for: version)?.url
                )
            )
        }

        return options
    }
}
// swiftlint:enable type_body_length

#Preview {
    BottleCreationView(newlyCreatedBottleURL: .constant(nil))
}
