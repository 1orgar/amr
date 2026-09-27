//
//  LibraryView.swift
//  AppleMusicRemoteIOS
//
//  Library Navigation with iTunes Remote Parity, Alphabetical Index Scrubber,
//  Playlists, Artists, Albums, Songs, and Genres.
//

import SwiftUI

public struct LibraryView: View {
    @ObservedObject var playerManager: PlayerManager
    @State private var selectedIndexLetter: String? = nil
    @State private var showingSettingsModal = false
    
    let alphabetSections = ["#"] + (65...90).map { String(UnicodeScalar($0)!) } + (1040...1071).map { String(UnicodeScalar($0)!) }
    
    public var body: some View {
        NavigationStack {
            ZStack(alignment: .trailing) {
                ScrollViewReader { proxy in
                    List {
                        // Section 1: Top Navigation Categories
                        Section {
                            NavigationLink(destination: PlaylistsListView(playerManager: playerManager)) {
                                LibraryCategoryRow(
                                    icon: "music.note.list",
                                    gradient: [Color(hex: "#FA2D48"), Color(hex: "#FF6B8B")],
                                    title: "Плейлисты",
                                    count: playerManager.playlists.count
                                )
                            }
                            
                            NavigationLink(destination: ArtistsListView(playerManager: playerManager)) {
                                LibraryCategoryRow(
                                    icon: "music.mic",
                                    gradient: [Color(hex: "#007AFF"), Color(hex: "#5856D6")],
                                    title: "Артисты",
                                    count: playerManager.artists.count
                                )
                            }
                            
                            NavigationLink(destination: AlbumsListView(playerManager: playerManager)) {
                                LibraryCategoryRow(
                                    icon: "square.stack",
                                    gradient: [Color(hex: "#FF9500"), Color(hex: "#FFCC00")],
                                    title: "Альбомы",
                                    count: playerManager.albums.count
                                )
                            }
                            
                            NavigationLink(destination: SongsListView(playerManager: playerManager)) {
                                LibraryCategoryRow(
                                    icon: "music.quarternote.3",
                                    gradient: [Color(hex: "#AF52DE"), Color(hex: "#5856D6")],
                                    title: "Песни",
                                    count: playerManager.songs.count
                                )
                            }
                            
                            NavigationLink(destination: GenresListView(playerManager: playerManager)) {
                                LibraryCategoryRow(
                                    icon: "guitars",
                                    gradient: [Color(hex: "#34C759"), Color(hex: "#30B0C7")],
                                    title: "Жанры",
                                    count: playerManager.genres.count
                                )
                            }
                        }
                        .listRowBackground(Color(white: 0.12).opacity(0.6))
                        
                        // Section 2: Recently Added Horizontal Scroll
                        Section(header: Text("Недавно добавленные").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(.white)) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(playerManager.recentlyAddedAlbums) { album in
                                        RecentAlbumCard(album: album) {
                                            playerManager.playAlbum(album.id)
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        }
                        
                        // Section 3: All Songs with Alphabetical Section Headers
                        ForEach(playerManager.groupedSongsByLetter, id: \.letter) { section in
                            Section(header: Text(section.letter).font(.system(size: 15, weight: .bold)).foregroundColor(.amrRed).id(section.letter)) {
                                ForEach(section.songs) { song in
                                    TrackRowView(
                                        song: song,
                                        onPlay: {
                                            AMRHaptics.trackSkip()
                                            playerManager.playTrack(song.id)
                                        },
                                        onAction: {
                                            playerManager.presentActionSheet(for: song)
                                        }
                                    )
                                }
                            }
                            .listRowBackground(Color(white: 0.10).opacity(0.7))
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color.black.ignoresSafeArea())
                }
                
                // Vertical Alphabetical Index Scrubber
                AlphabetScrubberView(
                    alphabet: alphabetSections,
                    selectedLetter: $selectedIndexLetter,
                    onLetterSelected: { letter in
                        AMRHaptics.scrubberTick()
                        // Scroll to section id
                    }
                )
                .padding(.trailing, 4)
            }
            .navigationTitle("Медиатека")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettingsModal = true }) {
                        Image(systemName: "bonjour")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
        }
    }
}

// MARK: - Subcomponents
public struct LibraryCategoryRow: View {
    let icon: String
    let gradient: [Color]
    let title: String
    let count: Int
    
    public var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
            
            Spacer()
            
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.4))
            }
        }
        .padding(.vertical, 4)
    }
}
