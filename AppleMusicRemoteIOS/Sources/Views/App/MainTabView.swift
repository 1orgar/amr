//
//  MainTabView.swift
//  AppleMusicRemoteIOS
//
//  Master 5-tab navigation with floating mini player and Now Playing modal
//

import SwiftUI

public struct MainTabView: View {
    @StateObject private var store = PlayerStore.shared
    @State private var showFullPlayer: Bool = false

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            // 5 Tabs
            TabView(selection: $store.selectedTab) {
                // Tab 0: Now Playing direct screen
                NowPlayingView(store: store)
                    .tabItem {
                        Label("Слушать", systemImage: "play.circle.fill")
                    }
                    .tag(0)

                // Tab 1: Radio & Stations
                StationsView(store: store)
                    .tabItem {
                        Label("Радио", systemImage: "radio")
                    }
                    .tag(1)

                // Tab 2: Library
                LibraryView(store: store)
                    .tabItem {
                        Label("Медиатека", systemImage: "music.note.house.fill")
                    }
                    .tag(2)

                // Tab 3: Search
                UnifiedSearchView(store: store)
                    .tabItem {
                        Label("Поиск", systemImage: "magnifyingglass")
                    }
                    .tag(3)

                // Tab 4: Queue & Devices
                QueueView(store: store)
                    .tabItem {
                        Label("Очередь", systemImage: "list.bullet")
                    }
                    .tag(4)
            }
            .tint(.amrRed)

            // Floating Mini Player (visible on tabs 1..4 when track is active)
            if store.selectedTab != 0 && store.currentTrack != nil {
                MiniPlayerView(store: store) {
                    showFullPlayer = true
                }
                .padding(.bottom, 54) // Above tab bar
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showFullPlayer) {
            NowPlayingView(store: store)
        }
        .sheet(isPresented: $store.showDiscoverySheet) {
            ServerDiscoverySheet(store: store)
        }
        .onAppear {
            if !store.isConnected {
                store.connectToDefaultOrScan()
            }
        }
    }
}
