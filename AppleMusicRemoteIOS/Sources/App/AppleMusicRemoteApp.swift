//
//  AppleMusicRemoteApp.swift
//  AppleMusicRemoteIOS
//
//  Application entry point for native iPhone client
//

import SwiftUI

@main
public struct AppleMusicRemoteApp: App {
    @ObservedObject private var store = PlayerStore.shared

    public init() {}

    public var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.dark)
        }
    }
}
