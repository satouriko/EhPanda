//
//  EhPandaApp.swift
//  EhPanda
//
//  Created by 荒木辰造 on R 2/10/28.
//

import SwiftUI
import Kingfisher
import SDWebImageSwiftUI

@main
struct EhPandaApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            Home()
                .environmentObject(store)
                .accentColor(accentColor)
                .onOpenURL(perform: onOpenURL)
                .onAppear(perform: onStartTasks)
                .preferredColorScheme(preferredColorScheme)
        }
    }
}

private extension EhPandaApp {
    var setting: Setting? {
        store.appState.settings.setting
    }
    var accentColor: Color? {
        setting?.accentColor
    }
    var preferredColorScheme: ColorScheme? {
        setting?.colorScheme ?? .none
    }

    func onStartTasks() {
        configureWebImage()
        configureDomainFronting()
        clearImageCachesIfNeeded()
    }
    func onOpenURL(_ url: URL) {
        switch url.host {
        case "token":
            setToken(with: url.pathComponents.last)
        case "debugMode":
            setDebugMode(with: url.pathComponents.last == "on")
        default:
            break
        }
    }

    func configureDomainFronting() {
        DFManager.shared.dfState = setting?.bypassSNIFiltering
            == true ? .activated : .notActivated
    }
    func configureWebImage() {
        let config = KingfisherManager.shared.downloader.sessionConfiguration
        if setting?.bypassSNIFiltering == true {
            config.protocolClasses = [DFURLProtocol.self]
        }
        config.httpCookieStorage = HTTPCookieStorage.shared
        KingfisherManager.shared.downloader.sessionConfiguration = config
    }
    func clearImageCachesIfNeeded() {
        let threshold = 200 * 1024 * 1024

        if SDImageCache.shared.totalDiskSize() > threshold {
            SDImageCache.shared.clearDisk()
        }
        KingfisherManager.shared.cache.calculateDiskStorageSize { result in
            if case .success(let size) = result {
                if size > threshold {
                    KingfisherManager.shared.cache.clearDiskCache()
                }
            }
        }
    }
}
