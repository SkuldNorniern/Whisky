//
//  ConfigView.swift
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
import AppKit

// swiftlint:disable file_length type_body_length

enum LoadingState {
    case loading
    case modifying
    case success
    case failed
}

enum RuntimeSelection: String, CaseIterable {
    case builtin
    case custom

    var title: String {
        switch self {
        case .builtin:
            return "Built-in"
        case .custom:
            return "Custom"
        }
    }
}

private struct RuntimePreset: Hashable {
    let label: String
    let source: String
    let selectionVersion: SemanticVersion?
    let majorTrack: Int?
    let url: URL
}

private struct RuntimeOption: Hashable {
    let id: String
    let version: SemanticVersion
    let source: String
    let url: URL?
}

struct ConfigView: View {
    private static let excludedRuntimeVersions: Set<SemanticVersion> = [
        SemanticVersion(11, 2, 1)
    ]

    private static let runtimePresets: [RuntimePreset] = [
        (
            "7.7", "Whisky Official", SemanticVersion(7, 7, 0), nil,
            "https://data.getwhisky.app/Wine/Libraries.tar.gz"
        ),
        (
            "8.0.1", "Wine Official", SemanticVersion(8, 0, 1), nil,
            "https://github.com/Gcenx/macOS_Wine_builds/releases/download/8.0.1/wine-stable-8.0.1-osx64.tar.xz"
        ),
        (
            "9.21", "Wine Official", SemanticVersion(9, 21, 0), nil,
            "https://github.com/Gcenx/macOS_Wine_builds/releases/download/9.21/wine-devel-9.21-osx64.tar.xz"
        ),
        (
            "11.2", "Wine Official", SemanticVersion(11, 2, 0), nil,
            "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.2/wine-devel-11.2-osx64.tar.xz"
        )
    ].compactMap { label, source, version, majorTrack, urlString in
        guard let url = URL(string: urlString) else { return nil }
        return RuntimePreset(label: label,
                             source: source,
                             selectionVersion: version,
                             majorTrack: majorTrack,
                             url: url)
    }

    @ObservedObject var bottle: Bottle
    @State private var buildVersion: String = ""
    @State private var retinaMode: Bool = false
    @State private var dpiConfig: Int = 96
    @State private var detectedBottleRuntimeVersion: String = "Detecting..."
    @State private var launchErrorMessage: String?
    @State private var winVersionLoadingState: LoadingState = .loading
    @State private var buildVersionLoadingState: LoadingState = .loading
    @State private var retinaModeLoadingState: LoadingState = .loading
    @State private var dpiConfigLoadingState: LoadingState = .loading
    @State private var runtimeLoadingState: LoadingState = .loading
    @State private var dpiSheetPresented: Bool = false
    @State private var runtimeSelection: RuntimeSelection = .builtin
    @State private var builtinRuntimeOptions: [RuntimeOption] = []
    @State private var selectedBuiltinRuntimeID: String = ""
    @State private var pendingBuiltinRuntimeID: String = ""
    @State private var customRuntimePath: String = ""
    @State private var runtimeErrorMessage: String?
    @State private var officialRuntimeCatalog: [WhiskyWineDistribution.RuntimeCatalogEntry] = []
    @State private var runtimeInstallerPresented: Bool = false
    @State private var runtimeInstallerPath: [SetupStage] = []
    @State private var runtimeInstallerTarLocation: URL = URL(fileURLWithPath: "")
    @State private var runtimeInstallTargetVersion: SemanticVersion?
    @State private var runtimeInstallTargetURL: URL?
    @AppStorage("wineSectionExpanded") private var wineSectionExpanded: Bool = true
    @AppStorage("dxvkSectionExpanded") private var dxvkSectionExpanded: Bool = true
    @AppStorage("metalSectionExpanded") private var metalSectionExpanded: Bool = true

    var body: some View {
        Form {
            Section("config.title.wine", isExpanded: $wineSectionExpanded) {
                HStack {
                    Text("Active Runtime (Bottle)")
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(activeRuntimeSummary)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                SettingItemView(title: "Runtime Type", loadingState: runtimeLoadingState) {
                    Picker("Runtime Type", selection: $runtimeSelection) {
                        ForEach(RuntimeSelection.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .onChange(of: runtimeSelection) { _, newValue in
                        guard runtimeLoadingState == .success else { return }
                        switch newValue {
                        case .builtin:
                            let targetVersion = selectedBuiltinRuntimeVersion
                            applyBuiltinRuntime(version: targetVersion)
                        case .custom:
                            if !customRuntimePath.isEmpty {
                                applyCustomRuntime(path: customRuntimePath)
                            }
                        }
                    }
                }

                if runtimeSelection == .builtin {
                    SettingItemView(title: "Runtime Version", loadingState: runtimeLoadingState) {
                        HStack {
                            Picker("Runtime Version", selection: $pendingBuiltinRuntimeID) {
                                ForEach(builtinRuntimeOptions, id: \.id) { option in
                                    Text(runtimeDisplayName(for: option))
                                        .tag(option.id)
                                }
                            }

                            Button("Apply") {
                                applyBuiltinRuntime(version: pendingBuiltinRuntimeVersion)
                            }
                            .disabled(selectedBuiltinRuntimeID == pendingBuiltinRuntimeID)
                        }
                    }

                    if !isBuiltinRuntimeInstalled(pendingBuiltinRuntimeVersion) {
                        Text("Selected runtime is not installed locally yet.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else {
                    SettingItemView(title: "Custom Runtime", loadingState: runtimeLoadingState) {
                        HStack {
                            Text(customRuntimePath.isEmpty ? "Not set" : customRuntimePath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(customRuntimePath.isEmpty ? .secondary : .primary)
                            Button("Browse") {
                                openCustomRuntimePicker()
                            }
                        }
                    }
                }

                if let runtimeErrorMessage {
                    Text(runtimeErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                SettingItemView(title: "config.winVersion", loadingState: winVersionLoadingState) {
                    Picker("config.winVersion", selection: $bottle.settings.windowsVersion) {
                        ForEach(WinVersion.allCases.reversed(), id: \.self) {
                            Text($0.pretty())
                        }
                    }
                }
                SettingItemView(title: "config.buildVersion", loadingState: buildVersionLoadingState) {
                    TextField("config.buildVersion", text: $buildVersion)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(PlainTextFieldStyle())
                        .onSubmit {
                            buildVersionLoadingState = .modifying
                            Task(priority: .userInitiated) {
                                do {
                                    let trimmed = buildVersion.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard let parsedVersion = Int(trimmed), parsedVersion > 0 else {
                                        buildVersionLoadingState = .failed
                                        return
                                    }

                                    try await Wine.changeBuildVersion(bottle: bottle, version: parsedVersion)
                                    buildVersionLoadingState = .success
                                } catch {
                                    print("Failed to change build version")
                                    buildVersionLoadingState = .failed
                                }
                            }
                        }
                }
                SettingItemView(title: "config.retinaMode", loadingState: retinaModeLoadingState) {
                    Toggle("config.retinaMode", isOn: $retinaMode)
                        .onChange(of: retinaMode, { _, newValue in
                            Task(priority: .userInitiated) {
                                retinaModeLoadingState = .modifying
                                do {
                                    try await Wine.changeRetinaMode(bottle: bottle, retinaMode: newValue)
                                    retinaModeLoadingState = .success
                                } catch {
                                    print("Failed to change build version")
                                    retinaModeLoadingState = .failed
                                }
                            }
                        })
                }
                Picker("config.enhancedSync", selection: $bottle.settings.enhancedSync) {
                    Text("config.enhancedSync.none").tag(EnhancedSync.none)
                    Text("config.enhacnedSync.esync").tag(EnhancedSync.esync)
                    Text("config.enhacnedSync.msync").tag(EnhancedSync.msync)
                }
                SettingItemView(title: "config.dpi", loadingState: dpiConfigLoadingState) {
                    Button("config.inspect") {
                        dpiSheetPresented = true
                    }
                    .sheet(isPresented: $dpiSheetPresented) {
                        DPIConfigSheetView(
                            dpiConfig: $dpiConfig,
                            isRetinaMode: $retinaMode,
                            presented: $dpiSheetPresented
                        )
                    }
                }
                if #available(macOS 15, *) {
                    Toggle(isOn: $bottle.settings.avxEnabled) {
                        VStack(alignment: .leading) {
                            Text("config.avx")
                            if bottle.settings.avxEnabled {
                                HStack(alignment: .firstTextBaseline) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .symbolRenderingMode(.multicolor)
                                        .font(.subheadline)
                                    Text("config.avx.warning")
                                        .fontWeight(.light)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                }
            }
            Section("config.title.dxvk", isExpanded: $dxvkSectionExpanded) {
                Toggle(isOn: $bottle.settings.dxvk) {
                    Text("config.dxvk")
                }
                Toggle(isOn: $bottle.settings.dxvkAsync) {
                    Text("config.dxvk.async")
                }
                .disabled(!bottle.settings.dxvk)
                Picker("config.dxvkHud", selection: $bottle.settings.dxvkHud) {
                    Text("config.dxvkHud.full").tag(DXVKHUD.full)
                    Text("config.dxvkHud.partial").tag(DXVKHUD.partial)
                    Text("config.dxvkHud.fps").tag(DXVKHUD.fps)
                    Text("config.dxvkHud.off").tag(DXVKHUD.off)
                }
                .disabled(!bottle.settings.dxvk)
            }
            Section("config.title.metal", isExpanded: $metalSectionExpanded) {
                Toggle(isOn: $bottle.settings.metalHud) {
                    Text("config.metalHud")
                }
                Toggle(isOn: $bottle.settings.metalTrace) {
                    Text("config.metalTrace")
                    Text("config.metalTrace.info")
                }
                if let device = MTLCreateSystemDefaultDevice() {
                    // Represents the Apple family 9 GPU features that correspond to the Apple A17, M3, and M4 GPUs.
                    if device.supportsFamily(.apple9) {
                        Toggle(isOn: $bottle.settings.dxrEnabled) {
                            Text("config.dxr")
                            Text("config.dxr.info")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .animation(.whiskyDefault, value: wineSectionExpanded)
        .animation(.whiskyDefault, value: dxvkSectionExpanded)
        .animation(.whiskyDefault, value: metalSectionExpanded)
        .bottomBar {
            HStack {
                Spacer()
                Button("config.controlPanel") {
                    Task(priority: .userInitiated) {
                        do {
                            try await Wine.control(bottle: bottle)
                        } catch {
                            launchErrorMessage = "Failed to launch Control Panel: \(error.localizedDescription)"
                        }
                    }
                }
                Button("config.regedit") {
                    Task(priority: .userInitiated) {
                        do {
                            try await Wine.regedit(bottle: bottle)
                        } catch {
                            launchErrorMessage = "Failed to launch Registry Editor: \(error.localizedDescription)"
                        }
                    }
                }
                Button("config.winecfg") {
                    Task(priority: .userInitiated) {
                        do {
                            try await Wine.cfg(bottle: bottle)
                        } catch {
                            launchErrorMessage = "Failed to launch Wine Configuration: \(error.localizedDescription)"
                        }
                    }
                }
            }
            .padding()
        }
        .alert("Launch Failed", isPresented: Binding(
            get: { launchErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    launchErrorMessage = nil
                }
            }
        )) {
            Button("OK") {
                launchErrorMessage = nil
            }
        } message: {
            Text(launchErrorMessage ?? "Unknown error")
        }
        .navigationTitle("tab.config")
        .onAppear {
            winVersionLoadingState = .success
            refreshDetectedBottleRuntimeVersion()
            loadRuntimeConfiguration()
            loadOfficialRuntimeCatalog()

            loadBuildName()

            Task(priority: .userInitiated) {
                do {
                    retinaMode = try await Wine.retinaMode(bottle: bottle)
                    retinaModeLoadingState = .success
                } catch {
                    print(error)
                    retinaModeLoadingState = .failed
                }
            }
            Task(priority: .userInitiated) {
                do {
                    dpiConfig = try await Wine.dpiResolution(bottle: bottle) ?? 0
                    dpiConfigLoadingState = .success
                } catch {
                    print(error)
                    // If DPI has not yet been edited, there will be no registry entry
                    dpiConfigLoadingState = .success
                }
            }
        }
        .onChange(of: bottle.settings.windowsVersion) { _, newValue in
            if winVersionLoadingState == .success {
                winVersionLoadingState = .loading
                buildVersionLoadingState = .loading
                Task(priority: .userInitiated) {
                    do {
                        try await Wine.changeWinVersion(bottle: bottle, win: newValue)
                        winVersionLoadingState = .success
                        bottle.settings.windowsVersion = newValue
                        loadBuildName()
                    } catch {
                        print(error)
                        winVersionLoadingState = .failed
                    }
                }
            }
        }
        .onChange(of: dpiConfig) {
            if dpiConfigLoadingState == .success {
                Task(priority: .userInitiated) {
                    dpiConfigLoadingState = .modifying
                    do {
                        try await Wine.changeDpiResolution(bottle: bottle, dpi: dpiConfig)
                        dpiConfigLoadingState = .success
                    } catch {
                        print(error)
                        dpiConfigLoadingState = .failed
                    }
                }
            }
        }
        .sheet(isPresented: $runtimeInstallerPresented) {
            runtimeInstallerView
        }
    }

    func loadBuildName() {
        Task(priority: .userInitiated) {
            do {
                if let buildVersionString = try await Wine.buildVersion(bottle: bottle) {
                    buildVersion = buildVersionString
                } else {
                    buildVersion = ""
                }

                buildVersionLoadingState = .success
            } catch {
                print(error)
                buildVersionLoadingState = .failed
            }
        }
    }

    func refreshDetectedBottleRuntimeVersion() {
        Task(priority: .userInitiated) {
            do {
                let output = try await Wine.runWine(["--version"], bottle: bottle)
                await MainActor.run {
                    detectedBottleRuntimeVersion = parseWineVersion(output)
                }
            } catch {
                await MainActor.run {
                    detectedBottleRuntimeVersion = "Unavailable"
                }
            }
        }
    }

    func loadRuntimeConfiguration() {
        runtimeLoadingState = .modifying
        runtimeErrorMessage = nil

        var available = WhiskyWineInstaller.availableBuiltinWineVersions()
            .filter { !Self.excludedRuntimeVersions.contains($0) }
        for preset in Self.runtimePresets {
            guard let presetVersion = resolvedPresetVersion(for: preset) else { continue }
            guard !Self.excludedRuntimeVersions.contains(presetVersion) else { continue }
            if !available.contains(presetVersion) {
                available.append(presetVersion)
            }
        }
        if case .builtin(let runtimeVersion) = bottle.settings.wineRuntime,
           !available.contains(runtimeVersion) {
            available.insert(runtimeVersion, at: 0)
        }
        builtinRuntimeOptions = buildRuntimeOptions(from: available)

        switch bottle.settings.wineRuntime {
        case .builtin(let version):
            runtimeSelection = .builtin
            let selectedOption = builtinRuntimeOptions.first(where: { $0.version == version })
                ?? builtinRuntimeOptions.first
            selectedBuiltinRuntimeID = selectedOption?.id ?? ""
            pendingBuiltinRuntimeID = selectedBuiltinRuntimeID
        case .custom(let path):
            runtimeSelection = .custom
            customRuntimePath = path
        }

        runtimeLoadingState = .success
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

    func officialCatalogEntry(for version: SemanticVersion) -> WhiskyWineDistribution.RuntimeCatalogEntry? {
        officialRuntimeCatalog.first(where: { $0.version == version })
    }

    private func runtimeDisplayName(for option: RuntimeOption) -> String {
        let version = option.version
        let versionString = "\(version.major).\(version.minor).\(version.patch)"
        let installSuffix = isBuiltinRuntimeInstalled(version) ? "" : " [Not installed]"
        return "\(versionString) (\(option.source))\(installSuffix)"
    }

    func selectedRuntimeURL(for version: SemanticVersion) -> URL? {
        if let option = builtinRuntimeOptions.first(where: { $0.version == version }) {
            return option.url
        }
        if let preset = preset(for: version) {
            return resolvedPresetURL(for: preset)
        }
        return officialCatalogEntry(for: version)?.url
    }

    func selectedRuntimeSource(for version: SemanticVersion) -> String {
        if selectedBuiltinRuntimeVersion == version,
           let selectedOption = builtinRuntimeOptions.first(where: { $0.id == selectedBuiltinRuntimeID }) {
            return selectedOption.source
        }

        if let option = builtinRuntimeOptions.first(where: { $0.version == version }) {
            return option.source
        }
        if let preset = preset(for: version) {
            return preset.source
        }
        return officialCatalogEntry(for: version)?.source.rawValue ?? "Unknown"
    }

    var selectedBuiltinRuntimeVersion: SemanticVersion {
        builtinRuntimeOptions.first(where: { $0.id == selectedBuiltinRuntimeID })?.version
            ?? WhiskyWineDistribution.defaultWineVersion
    }

    var pendingBuiltinRuntimeVersion: SemanticVersion {
        builtinRuntimeOptions.first(where: { $0.id == pendingBuiltinRuntimeID })?.version
            ?? selectedBuiltinRuntimeVersion
    }

    var pendingBuiltinRuntimeURL: URL? {
        builtinRuntimeOptions.first(where: { $0.id == pendingBuiltinRuntimeID })?.url
    }

    func isBuiltinRuntimeInstalled(_ version: SemanticVersion) -> Bool {
        WhiskyWineInstaller.isBuiltinVersionInstalled(version)
    }

    private func preset(for version: SemanticVersion) -> RuntimePreset? {
        Self.runtimePresets.first(where: { resolvedPresetVersion(for: $0) == version })
    }

    private func resolvedPresetVersion(for preset: RuntimePreset) -> SemanticVersion? {
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

    private func resolvedPresetURL(for preset: RuntimePreset) -> URL? {
        if preset.selectionVersion != nil,
           preset.source == "Wine Official" {
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

    private func buildRuntimeOptions(from versions: [SemanticVersion]) -> [RuntimeOption] {
        var options: [RuntimeOption] = []

        for preset in Self.runtimePresets {
            guard let version = resolvedPresetVersion(for: preset), versions.contains(version) else { continue }
            options.append(
                RuntimeOption(
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
                RuntimeOption(
                    id: "version:\(version.major).\(version.minor).\(version.patch)",
                    version: version,
                    source: officialCatalogEntry(for: version)?.source.rawValue ?? "Installed",
                    url: officialCatalogEntry(for: version)?.url
                )
            )
        }

        return options
    }

    var activeRuntimeSummary: String {
        switch bottle.settings.wineRuntime {
        case .builtin(let version):
            let source = selectedRuntimeSource(for: version)
            return "\(detectedBottleRuntimeVersion) (\(source))"
        case .custom:
            return "\(detectedBottleRuntimeVersion) (Custom)"
        }
    }

    @ViewBuilder
    var runtimeInstallerView: some View {
        if let runtimeInstallTargetURL {
            NavigationStack(path: $runtimeInstallerPath) {
                WhiskyWineDownloadView(
                    tarLocation: $runtimeInstallerTarLocation,
                    path: $runtimeInstallerPath,
                    runtimeArchiveURL: runtimeInstallTargetURL
                )
                .navigationBarBackButtonHidden(true)
                .navigationDestination(for: SetupStage.self) { stage in
                    switch stage {
                    case .whiskyWineInstall:
                        WhiskyWineInstallView(
                            tarLocation: $runtimeInstallerTarLocation,
                            path: $runtimeInstallerPath,
                            showSetup: $runtimeInstallerPresented,
                            installAction: { archiveURL in
                                guard let runtimeInstallTargetVersion else { return false }
                                return await WhiskyWineInstaller.installBuiltinRuntime(
                                    version: runtimeInstallTargetVersion,
                                    from: archiveURL
                                )
                            },
                            onInstallCompleted: {
                                if let runtimeInstallTargetVersion {
                                    bottle.settings.wineRuntime = .builtin(version: runtimeInstallTargetVersion)
                                    if let selectedOption = builtinRuntimeOptions.first(
                                        where: { $0.version == runtimeInstallTargetVersion }
                                    ) {
                                        selectedBuiltinRuntimeID = selectedOption.id
                                        pendingBuiltinRuntimeID = selectedOption.id
                                    }
                                    runtimeErrorMessage = nil
                                    runtimeLoadingState = .success
                                    loadRuntimeConfiguration()
                                    refreshDetectedBottleRuntimeVersion()
                                }
                            }
                        )
                    case .rosetta, .whiskyWineDownload:
                        EmptyView()
                    }
                }
            }
            .padding()
            .interactiveDismissDisabled()
        } else {
            EmptyView()
        }
    }

    func startRuntimeInstall(version: SemanticVersion) {
        guard let selectedURL = pendingBuiltinRuntimeURL ?? selectedRuntimeURL(for: version) else {
            runtimeErrorMessage = "No download URL is available for this runtime."
            runtimeLoadingState = .success
            return
        }

        let ext = selectedURL.pathExtension.lowercased()
        guard ext == "gz" || ext == "xz" else {
            runtimeErrorMessage = "No direct runtime archive is available for this selection yet."
            runtimeLoadingState = .success
            return
        }

        runtimeInstallTargetVersion = version
        runtimeInstallTargetURL = selectedURL
        runtimeInstallerPath = []
        runtimeInstallerTarLocation = URL(fileURLWithPath: "")
        runtimeInstallerPresented = true
    }

    func applyBuiltinRuntime(version: SemanticVersion) {
        runtimeLoadingState = .modifying
        runtimeErrorMessage = nil

        guard isBuiltinRuntimeInstalled(version) else {
            startRuntimeInstall(version: version)
            runtimeLoadingState = .success
            return
        }

        bottle.settings.wineRuntime = .builtin(version: version)
        selectedBuiltinRuntimeID = pendingBuiltinRuntimeID
        runtimeLoadingState = .success
        refreshDetectedBottleRuntimeVersion()
    }

    func applyCustomRuntime(path: String) {
        runtimeLoadingState = .modifying

        do {
            let validatedBin = try WhiskyWineInstaller.validateCustomRuntime(path: path)
            let normalizedPath = validatedBin.path(percentEncoded: false)
            bottle.settings.wineRuntime = .custom(path: normalizedPath)
            customRuntimePath = normalizedPath
            runtimeErrorMessage = nil
            runtimeLoadingState = .success
            refreshDetectedBottleRuntimeVersion()
        } catch {
            runtimeErrorMessage = error.localizedDescription
            runtimeLoadingState = .success
        }
    }

    func openCustomRuntimePicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose Wine Runtime"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let selectedURL = panel.url {
            applyCustomRuntime(path: selectedURL.path(percentEncoded: false))
        }
    }

    func parseWineVersion(_ output: String) -> String {
        let trimmed = output
            .replacingOccurrences(of: "wine-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let firstToken = trimmed.split(whereSeparator: { $0.isWhitespace }).first {
            return String(firstToken)
        }

        return trimmed.isEmpty ? "Unavailable" : trimmed
    }

}

struct DPIConfigSheetView: View {
    @Binding var dpiConfig: Int
    @Binding var isRetinaMode: Bool
    @Binding var presented: Bool
    @State var stagedChanges: Float
    @FocusState var textFocused: Bool

    init(dpiConfig: Binding<Int>, isRetinaMode: Binding<Bool>, presented: Binding<Bool>) {
        self._dpiConfig = dpiConfig
        self._isRetinaMode = isRetinaMode
        self._presented = presented
        self.stagedChanges = Float(dpiConfig.wrappedValue)
    }

    var body: some View {
        VStack {
            HStack {
                Text("configDpi.title")
                    .fontWeight(.bold)
                Spacer()
            }
            Divider()
            GroupBox(label: Label("configDpi.preview", systemImage: "text.magnifyingglass")) {
                VStack {
                    HStack {
                        Text("configDpi.previewText")
                            .padding(16)
                            .font(.system(size:
                                (10 * CGFloat(stagedChanges)) / 72 *
                                          (isRetinaMode ? 0.5 : 1)
                            ))
                        Spacer()
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: 80)
            }
            HStack {
                Slider(value: $stagedChanges, in: 96...480, step: 24, onEditingChanged: { _ in
                    textFocused = false
                })
                TextField(String(), value: $stagedChanges, format: .number)
                    .frame(width: 40)
                    .focused($textFocused)
                Text("configDpi.dpi")
            }
            Spacer()
            HStack {
                Spacer()
                Button("create.cancel") {
                    presented = false
                }
                .keyboardShortcut(.cancelAction)
                Button("button.ok") {
                    dpiConfig = Int(stagedChanges)
                    presented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: ViewWidth.medium, height: 240)
    }
}

struct SettingItemView<Content: View>: View {
    let title: String.LocalizationValue
    let loadingState: LoadingState
    @ViewBuilder var content: () -> Content

    @Namespace private var viewId
    @Namespace private var progressViewId

    var body: some View {
        HStack {
            Text(String(localized: title))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                switch loadingState {
                case .loading, .modifying:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .matchedGeometryEffect(id: progressViewId, in: viewId)
                case .success:
                    content()
                        .labelsHidden()
                        .disabled(loadingState != .success)
                case .failed:
                    Text("config.notAvailable")
                        .font(.caption).foregroundStyle(.red)
                        .multilineTextAlignment(.trailing)
                }
            }
            .animation(.default, value: loadingState)
        }
    }
}

// swiftlint:enable file_length type_body_length
