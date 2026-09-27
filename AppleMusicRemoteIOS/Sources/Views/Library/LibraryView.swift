//
//  LibraryView.swift
//  AppleMusicRemoteIOS
//
//  Full iTunes Remote library parity: Playlists, Artists, Albums, Songs, Genres
//

import SwiftUI

public struct LibraryView: View {
    @ObservedObject public var store: PlayerStore

    public init(store: PlayerStore = .shared) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List {
                // Categories
                Section {
                    NavigationLink(destination: PlaylistsListView(store: store)) {
                        CategoryRow(icon: "music.note.list", title: "Плейлисты", count: store.playlists.count, color: .amrRed)
                    }

                    NavigationLink(destination: ArtistsListView(store: store)) {
                        CategoryRow(icon: "music.mic", title: "Артисты", count: store.artists.count, color: .purple)
                    }

                    NavigationLink(destination: SongsListView(store: store)) {
                        CategoryRow(icon: "music.note", title: "Песни", count: store.songs.count, color: .blue)
                    }
                }
                .listRowBackground(Color.amrSurfaceGlass)

                // Quick Playlists list right in the library view
                if !store.playlists.isEmpty {
                    Section(header: Text("Плейлисты").foregroundColor(.amrTextSecondary).font(.system(size: 14, weight: .semibold))) {
                        ForEach(store.playlists) { pl in
                            NavigationLink(destination: PlaylistDetailView(playlist: pl, store: store)) {
                                HStack(spacing: 14) {
                                    RemoteImageView(urlString: pl.artworkUrl, cornerRadius: 8, placeholderIcon: "music.note.list")
                                        .frame(width: 44, height: 44)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pl.name)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.white)
                                        Text("\(pl.trackCount) треков")
                                            .font(.system(size: 13))
                                            .foregroundColor(.amrTextSecondary)
                                    }

                                    Spacer()
                                }
                            }
                            .listRowBackground(Color.amrSurfaceGlass)
                        }
                    }
                }
            }
            .navigationDestination(item: $store.selectedPlaylist) { pl in
                PlaylistDetailView(playlist: pl, store: store)
            }
            .scrollContentBackground(.hidden)
            .background(Color.amrBackground.ignoresSafeArea())
            .navigationTitle("Медиатека")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        AMRHaptics.selection()
                        store.loadLibraryPlaylists()
                        store.loadLibrarySongs()
                        store.loadLibraryArtists()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.amrRed)
                    }
                }
            }
            .refreshable {
                store.loadLibraryPlaylists()
                store.loadLibrarySongs()
                store.loadLibraryArtists()
            }
            .onAppear {
                store.loadLibraryPlaylists()
                store.loadLibrarySongs()
                store.loadLibraryArtists()
            }
        }
    }
}

// MARK: - Category Row

private struct CategoryRow: View {
    let icon: String
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 28)

            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)

            Spacer()

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.amrTextTertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Subviews: Playlists, Artists, Songs

public struct PlaylistsListView: View {
    @ObservedObject public var store: PlayerStore

    public init(store: PlayerStore = .shared) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            if store.isLoadingPlaylists && store.playlists.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.amrRed)
                        .scaleEffect(1.2)
                    Text("Загрузка плейлистов...")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.amrTextSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else if store.playlists.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 44))
                        .foregroundColor(.amrTextTertiary)
                    Text("Нет плейлистов")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Плейлисты из приложения Музыка появятся здесь")
                        .font(.system(size: 14))
                        .foregroundColor(.amrTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button(action: {
                        AMRHaptics.selection()
                        store.loadLibraryPlaylists()
                    }) {
                        Label("Обновить", systemImage: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.amrRed)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.amrRed.opacity(0.12)))
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(store.playlists) { pl in
                        HStack(spacing: 0) {
                            NavigationLink(destination: PlaylistDetailView(playlist: pl, store: store)) {
                                HStack(spacing: 14) {
                                    RemoteImageView(urlString: pl.artworkUrl, cornerRadius: 10, placeholderIcon: "music.note.list")
                                        .frame(width: 52, height: 52)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(pl.name)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                        Text("\(pl.trackCount) треков")
                                            .font(.system(size: 13))
                                            .foregroundColor(.amrTextSecondary)
                                    }

                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            // Sibling Shuffle Button (not inside NavigationLink!)
                            Button(action: {
                                AMRHaptics.medium()
                                store.playPlaylist(name: pl.name, shuffle: true)
                            }) {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.amrTextSecondary)
                                    .padding(10)
                                    .background(Circle().fill(Color.white.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 8)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.amrTextTertiary)
                                .padding(.trailing, 8)
                        }
                        .padding(10)
                        .amrDarkGlass(cornerRadius: 14)
                    }
                }
                .padding(16)
            }
        }
        .background(Color.amrBackground.ignoresSafeArea())
        .navigationTitle("Плейлисты")
        .refreshable {
            store.loadLibraryPlaylists()
        }
        .onAppear {
            store.loadLibraryPlaylists()
        }
    }
}

public struct ArtistsListView: View {
    @ObservedObject public var store: PlayerStore

    public init(store: PlayerStore = .shared) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(store.artists) { artist in
                    Button(action: {
                        store.performSearch(query: artist.name, scope: "library")
                    }) {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(Color.amrSurfaceGlass)
                                .frame(width: 44, height: 44)
                                .overlay(Image(systemName: "person.fill").foregroundColor(.amrTextSecondary))

                            Text(artist.name)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.amrTextTertiary)
                        }
                        .padding(12)
                        .amrDarkGlass(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Color.amrBackground.ignoresSafeArea())
        .navigationTitle("Артисты")
        .onAppear {
            store.loadLibraryArtists()
        }
    }
}

public struct SongsListView: View {
    @ObservedObject public var store: PlayerStore
    @State private var selectedTrack: TrackItem?

    public init(store: PlayerStore = .shared) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(store.songs) { song in
                    TrackRowView(
                        track: song,
                        index: song.index,
                        isCurrent: store.currentTrack?.name == song.name && store.currentTrack?.artist == song.artist,
                        onPlay: {
                            let targetId = Int(song.id)
                            store.playPlaylist(name: "Медиатека", trackId: targetId, trackIndex: song.index, shuffle: false)
                        },
                        onMore: {
                            selectedTrack = song
                        }
                    )
                }
            }
            .padding(16)
        }
        .background(Color.amrBackground.ignoresSafeArea())
        .navigationTitle("Песни")
        .sheet(item: $selectedTrack) { trk in
            TrackActionSheet(track: trk, store: store)
        }
        .onAppear {
            store.loadLibrarySongs()
        }
    }
}
