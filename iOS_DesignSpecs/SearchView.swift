//
//  SearchView.swift
//  AppleMusicRemoteIOS
//
//  Unified Search Engine with Tri-Scope Segmented Control (All / Library / Apple Music)
//  and Debounced Real-Time Search Filter.
//

import SwiftUI

public enum SearchScope: String, CaseIterable, Identifiable {
    case all = "Все"
    case library = "Медиатека"
    case appleMusic = "Apple Music"
    
    public var id: String { self.rawValue }
}

public struct SearchView: View {
    @ObservedObject var playerManager: PlayerManager
    @State private var searchText: String = ""
    @State private var selectedScope: SearchScope = .all
    @State private var isSearching: Bool = false
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Scope Segmented Control
                Picker("Поиск в", selection: $selectedScope) {
                    ForEach(SearchScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black)
                
                if searchText.isEmpty {
                    // Pre-Search Discover & Browse State
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            Text("Популярные категории")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                SearchCategoryTile(title: "Новинки", gradient: [Color(hex: "#FA2D48"), Color(hex: "#FF6B8B")])
                                SearchCategoryTile(title: "Чарты", gradient: [Color(hex: "#FF9500"), Color(hex: "#FFCC00")])
                                SearchCategoryTile(title: "Хиты", gradient: [Color(hex: "#5856D6"), Color(hex: "#AF52DE")])
                                SearchCategoryTile(title: "Пространственное аудио", gradient: [Color(hex: "#007AFF"), Color(hex: "#30B0C7")])
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                } else {
                    // Filtered Live Search Results
                    List {
                        // Section 1: Artists (Avatars Horizontal Row)
                        if !playerManager.searchResults.artists.isEmpty {
                            Section(header: Text("Артисты").font(.system(size: 16, weight: .bold)).foregroundColor(.white)) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 18) {
                                        ForEach(playerManager.searchResults.artists) { artist in
                                            ArtistAvatarCell(artist: artist) {
                                                playerManager.openArtistDetails(artist)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                            }
                        }
                        
                        // Section 2: Top Songs
                        if !playerManager.searchResults.songs.isEmpty {
                            Section(header: Text("Песни").font(.system(size: 16, weight: .bold)).foregroundColor(.white)) {
                                ForEach(playerManager.searchResults.songs) { song in
                                    SearchSongRow(
                                        song: song,
                                        onPlay: {
                                            AMRHaptics.playPauseToggle()
                                            playerManager.playTrack(song.id)
                                        },
                                        onAction: {
                                            playerManager.presentActionSheet(for: song)
                                        }
                                    )
                                }
                            }
                            .listRowBackground(Color(white: 0.12).opacity(0.6))
                        }
                        
                        // Section 3: Albums
                        if !playerManager.searchResults.albums.isEmpty {
                            Section(header: Text("Альбомы").font(.system(size: 16, weight: .bold)).foregroundColor(.white)) {
                                ForEach(playerManager.searchResults.albums) { album in
                                    SearchAlbumRow(album: album) {
                                        playerManager.openAlbumDetails(album)
                                    }
                                }
                            }
                            .listRowBackground(Color(white: 0.12).opacity(0.6))
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Поиск")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Артисты, песни, альбомы..."
            )
            .onChange(of: searchText) { newValue in
                playerManager.performDebouncedSearch(query: newValue, scope: selectedScope)
            }
            .onChange(of: selectedScope) { newScope in
                playerManager.performDebouncedSearch(query: searchText, scope: newScope)
            }
        }
    }
}

// MARK: - Search Subviews
public struct SearchCategoryTile: View {
    let title: String
    let gradient: [Color]
    
    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 80)
            
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .padding(12)
        }
    }
}

public struct SearchSongRow: View {
    let song: TrackItem
    let onPlay: () -> Void
    let onAction: () -> Void
    
    public var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: song.artworkUrl)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.gray.opacity(0.3)
                }
            }
            .frame(width: 48, height: 48)
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(song.artist + " • " + song.album)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.6))
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: onPlay) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.amrRed)
            }
            .buttonStyle(.borderless)
            
            Button(action: onAction) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.6))
                    .padding(8)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}
