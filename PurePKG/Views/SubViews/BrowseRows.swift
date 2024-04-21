//
//  BrowseRows.swift
//  PurePKG
//
//  Created by Lrdsnow on 4/15/24.
//

import Foundation
import SwiftUI
import NukeUI

struct PlaceHolderRow: View {
    let alltweaks: Int
    let category: String
    let categoryTweaks: Int
    
    var body: some View {
        HStack {
            if !UserDefaults.standard.bool(forKey: "hideIcons") {
                VStack(alignment: .center) {
                    Spacer()
                    Image("DisplayAppIcon")
                        .resizable()
                        .scaledToFit()
#if os(tvOS)
                        .frame(width: 70, height: 70)
                        .customRadius(15)
#else
                        .frame(width: 50, height: 50)
                        .customRadius(11)
#endif
                    Spacer()
                }
#if os(tvOS)
                .padding(.trailing, -40)
#endif
            }
            VStack(alignment: .leading) {
                if alltweaks != -1 {
                    Text("All Tweaks")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("\(alltweaks) Tweaks Total")
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } else {
                    Text(category)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("\(categoryTweaks) Tweaks")
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
        }
    }
}

struct RepoRow: View {
    @EnvironmentObject var appData: AppData
    @State var repo: Repo
    
    var body: some View {
        HStack {
            if !UserDefaults.standard.bool(forKey: "hideIcons") {
                VStack(alignment: .center) {
                    Spacer()
                    LazyImage(url: (URL(string: repo.url.absoluteString.replacingOccurrences(of: "refreshing/", with: "")) ?? URL(fileURLWithPath: "/")).appendingPathComponent("CydiaIcon.png")) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .scaledToFit()
                        } else if state.error != nil {
                            Image("DisplayAppIcon")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .scaledToFit()
                        } else {
                            ProgressView()
                                .scaledToFit()
                        }
                    }
#if os(tvOS)
                    .frame(width: 70, height: 70)
                    .customRadius(15)
#else
                    .frame(width: 50, height: 50)
                    .customRadius(11)
#endif
                    Spacer()
                }
#if os(tvOS)
                .padding(.trailing, -40)
#endif
            }
            
            VStack(alignment: .leading) {
                Text(repo.name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("\(repo.url.absoluteString.replacingOccurrences(of: "/./", with: "").replacingOccurrences(of: "refreshing/", with: "").removeSubstringIfExists("/dists/"))\(repo.component != "main" ? " (\(repo.component))" : "")")
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if repo.error != nil {
                    Text(repo.error ?? "")
                        .font(.footnote)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
        }.contextMenu(menuItems: {
#if os(tvOS)
#else
            Button(action: {
#if os(macOS)
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(repo.url.absoluteString, forType: .string)
#else
                let pasteboard = UIPasteboard.general
                pasteboard.string = repo.url.absoluteString
#endif
            }) {
                Text("Copy Repo URL")
                Image(systemName: "doc.on.clipboard")
            }
#endif
            if #available(iOS 15.0, tvOS 15.0, *) {
                Button(role: .destructive, action: {
                    RepoHandler.removeRepo(repo.url)
                    refreshRepos(appData)
                }) {
                    Text("Delete Repo")
                    Image(systemName: "trash")
                }.foregroundColor(.red)
            } else {
                Button(action: {
                    RepoHandler.removeRepo(repo.url)
                    refreshRepos(appData)
                }) {
                    Text("Delete Repo")
                    Image(systemName: "trash")
                }.foregroundColor(.red)
            }
        })
    }
}

struct TweakRow: View {
    @EnvironmentObject var appData: AppData
    @State var tweak: Package
    
    var body: some View {
        HStack {
            if !UserDefaults.standard.bool(forKey: "hideIcons") {
                ZStack(alignment: .bottomTrailing) {
                    VStack(alignment: .center) {
                        Spacer()
                        LazyImage(url: tweak.icon) { state in
                            if let image = state.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .scaledToFit()
                            } else if state.error != nil {
                                Image("DisplayAppIcon")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .scaledToFit()
                            } else {
                                ProgressView()
                                    .scaledToFit()
                            }
                        }
#if os(tvOS)
                        .frame(width: 85, height: 85)
                        .customRadius(15)
#else
                        .frame(width: 50, height: 50)
                        .customRadius(11)
#endif
                        Spacer()
                    }
                    
                    if appData.installed_pkgs.contains(where: { $0.id == tweak.id }) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color.accentColor)
#if os(tvOS)
                            .offset(x: 15, y: -5)
#else
                            .offset(x: 5, y: -5)
#endif
                    }
                }
            }
            
            VStack(alignment: .leading) {
                Text(tweak.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text((tweak.installedVersion == "") ? "\(tweak.author) · \(tweak.version) · \(tweak.id)" : "\(tweak.author) · \(tweak.installedVersion) (\(tweak.version) available) · \(tweak.id)")
                    .font(.subheadline)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.5)
                Text(tweak.desc)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            
            if UserDefaults.standard.bool(forKey: "hideIcons") {
                if appData.installed_pkgs.contains(where: { $0.id == tweak.id }) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.accentColor)
                }
            }
        }.padding(.vertical, 5)
    }
}

