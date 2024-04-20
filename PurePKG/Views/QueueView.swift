//
//  QueuedView.swift
//  PurePKG
//
//  Created by Lrdsnow on 3/26/24.
//

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

struct QueueView: View {
    @EnvironmentObject var appData: AppData
    @State private var showLog = false
    @State private var editing = false
    @State private var installingQueue = false
    @State private var installLog = ""
    @State private var focused: Bool = false
    @State private var deps: [Package] = []
    @State private var toInstall: [Package] = []
    
    var body: some View {
        NavigationViewC {
            VStack(alignment: .leading) {
                if !showLog {
                    List {
                        if !appData.queued.install.isEmpty {
                            Section(content: {
                                ForEach(toInstall, id: \.id) { package in
                                    VStack {
                                        HStack {
                                            TweakRow(tweak: package)
                                                .padding(.leading, (deps.contains(where: { $0.id == package.id }) && !appData.queued.install.contains(where: { $0.id == package.id })) ? 10 : 0)
                                            Spacer()
                                            if editing && !(deps.contains(where: { $0.id == package.id }) && !appData.queued.install.contains(where: { $0.id == package.id }))  {
                                                Button(action: {
                                                    appData.queued.install.remove(at: appData.queued.install.firstIndex(where: { $0.id == package.id }) ?? -2)
                                                    appData.queued.all.remove(at: appData.queued.all.firstIndex(where: { $0 == package.id }) ?? -2)
                                                    refresh()
                                                }) {
                                                    Image(systemName: "trash").shadow(color: .accentColor, radius: 5)
                                                }
                                            }
                                        }.padding(.trailing)
                                        if installingQueue {
                                            VStack(alignment: .leading) {
                                                Text(appData.queued.status[package.id]?.message ?? "Queued...")
                                                ProgressView(value: appData.queued.status[package.id]?.percentage ?? 0)
                                                    .progressViewStyle(LinearProgressViewStyle())
                                                    .frame(height: 2)
                                            }
                                            .foregroundColor(.secondary).padding(.top, 5)
                                        }
                                    }.padding(.horizontal)
                                }
                            }, header: {
                                Text("Install/Upgrade").foregroundColor(.accentColor)
                                #if !os(iOS)
                                    .padding(.leading).padding(.top)
                                #endif
                            })
                        }
                        if !appData.queued.uninstall.isEmpty {
                            Section(content: {
                                ForEach(appData.queued.uninstall, id: \.id) { package in
                                    VStack {
                                        HStack {
                                            TweakRow(tweak: package)
                                            Spacer()
                                            if editing {
                                                Button(action: {
                                                    appData.queued.uninstall.remove(at: appData.queued.uninstall.firstIndex(where: { $0.id == package.id }) ?? -2)
                                                    appData.queued.all.remove(at: appData.queued.all.firstIndex(where: { $0 == package.id }) ?? -2)
                                                }) {
                                                    Image(systemName: "trash").shadow(color: .accentColor, radius: 5)
                                                }
                                            }
                                        }.padding(.trailing)
                                        if installingQueue {
                                            VStack(alignment: .leading) {
                                                Text(appData.queued.status[package.id]?.message ?? "Queued...")
                                                ProgressView(value: appData.queued.status[package.id]?.percentage ?? 0)
                                                    .progressViewStyle(LinearProgressViewStyle())
                                                    .frame(height: 2)
                                            }
                                            .foregroundColor(.secondary).padding(.top, 5)
                                        }
                                    }.padding(.horizontal)
                                }
                            }, header: {
                                Text("Uninstall").foregroundColor(.accentColor)
                                #if !os(iOS)
                                    .padding(.leading).padding(.top)
                                #endif
                            })
                        }
                    }
                } else {
                    Text(installLog).padding()
                }
                Spacer()
                InstallQueuedButton(showLog: $showLog, installingQueue: $installingQueue, installLog: $installLog, deps: $deps).padding().padding(.bottom, 30)
            }.listStyle(.plain).onAppear() {
                refresh()
            }
            #if os(iOS)
                .navigationBarTitleC("Queued")
            #endif
            #if !os(macOS)
                .navigationBarItems(trailing: HStack {
                        Button(action: {
                            editing.toggle()
                        }, label: {
                            Image(systemName: "pencil")
                        })
                })
            #endif
        }
    }
    
    private func refresh() {
        deps = RepoHandler.getDeps(appData.queued.install, appData)
        toInstall = appData.queued.install + deps.filter { dep in appData.queued.install.first(where: { $0.id == dep.id }) == nil }
    }
}

struct InstallQueuedButton: View {
    @EnvironmentObject var appData: AppData
    @Binding var showLog: Bool
    @Binding var installingQueue: Bool
    @Binding var installLog: String
    @Binding var deps: [Package]
    
    var body: some View {
        HStack {
            Spacer()
            Button(action: {
                if !showLog {
                    if Jailbreak.type(appData) == .jailed {
                        showPopup("bruh", "PurePKG is in demo mode, you cannot install tweaks")
                    } else {
                        installingQueue = true
                        #if targetEnvironment(simulator)
                        installLog += "Simulator doesnt support installing tweaks..."
                        showLog = true
                        #else
                        APTWrapper.performOperations(installs: appData.queued.install, removals: appData.queued.uninstall, installDeps: deps,
                        progressCallback: { _, statusValid, statusReadable, package in
                            log("STATUSINFO:\nStatusValid: \(statusValid)\nStatusReadable: \(statusReadable)\nPackage: \(package)")
                            var percent: Double = 0
                            if statusReadable.contains("Installed") {
                                percent = 1
                            } else if statusReadable.contains("Configuring") {
                                percent = 0.7
                            } else if statusReadable.contains("Preparing") {
                                percent = 0.4
                            }
                            DispatchQueue.main.async {
                                if appData.queued.status[package]?.percentage ?? 0 <= percent {
                                    appData.queued.status[package] = installStatus(message: statusReadable, percentage: percent)
                                }
                            }
                        },
                        outputCallback: { output, _ in installLog += "\(output)" },
                        completionCallback: { _, finish, refresh in log("completionCallback: \(finish)"); appData.installed_pkgs = RepoHandler.getInstalledTweaks(Jailbreak.path(appData)+"/Library/dpkg"); showLog = true })
                        #endif
                    }
                } else {
                    installingQueue = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        appData.queued = PKGQueue()
                        showLog = false
                    }
                }
            }, label: {
                Spacer()
                Text(showLog ? "Close" : "Perform Actions").padding()
                Spacer()
            }).borderedProminentButtonC().tintC(Color.accentColor.opacity(0.7))
            Spacer()
        }
    }
}