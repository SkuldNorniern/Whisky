//
//  WhiskyWineInstallView.swift
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

struct WhiskyWineInstallView: View {
    @State var installing: Bool = true
    @State var installFailed: Bool = false
    @Binding var tarLocation: URL
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool
    var installAction: ((URL) async -> Bool)?
    var onInstallCompleted: (() -> Void)?

    var body: some View {
        VStack {
            VStack {
                Text("setup.whiskywine.install")
                    .font(.title)
                    .fontWeight(.bold)
                Text("setup.whiskywine.install.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if installing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 80)
                } else if installFailed {
                    Image(systemName: "xmark.circle")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "checkmark.circle")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.green)
                }
                if installFailed {
                    Text("Runtime install failed. Please try again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Spacer()
        }
        .frame(width: 400, height: 200)
        .onAppear {
            Task {
                let didInstall = if let installAction {
                    await installAction(tarLocation)
                } else {
                    await WhiskyWineInstaller.install(from: tarLocation)
                }
                installing = false
                installFailed = !didInstall

                if didInstall {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    onInstallCompleted?()
                    proceed()
                }
            }
        }
    }

    @MainActor
    func proceed() {
        showSetup = false
    }
}
