//
//  PlaylistDetailView.swift
//  AppleMusicRemoteIOS
//
//  Rich playlist track listing with Play All, Shuffle, tap-to-play, and swipe actions
//

import SwiftUI

public struct PlaylistDetailView: View {
    public let playlist: PlaylistItem
    @ObservedObject public var store: PlayerStore

    @State private var selectedTrackForSheet: TrackItem?

    public init(playlist: PlaylistItem, store: PlayerStore = .shared) {
        self.playlist = playlist
        self.store = store
    }

    private var tracks: [TrackItem] {
        if let direct = store.playlistTracks[playlist.name] {
            return direct
        }
        let clean = playlist.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for (k, v) in store.playlistTracks {
            if k.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == clean {
                return v
            }
        }
        return []
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerView
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                // Play / Shuffle Buttons
                actionButtonsView
                    .padding(.horizontal, 20)

                // Tracks List
                if store.isLoadingPlaylistTracks && tracks.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.amrRed)
                            .scaleEffect(1.2)
                        Text("Загрузка треков...")
                            .font(.system(size: 14))
                            .foregroundColor(.amrTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else if tracks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 36))
                            .foregroundColor(.amrTextTertiary)
                        Text("В плейлисте нет треков")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.amrTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            trackRow(track: track, index: index + 1)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 100) // Padding for floating mini player
        }
        .background(Color.amrBackground.ignoresSafeArea())
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    AMRHaptics.selection()
                    store.loadPlaylistTracks(name: playlist.name)
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.amrRed)
                }
            }
        }
        .sheet(item: $selectedTrackForSheet) { track in
            TrackActionSheet(track: track, store: store)
        }
        .onAppear {
            store.loadPlaylistTracks(name: playlist.name)
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(spacing: 14) {
            // Artwork
            RemoteImageView(urlString: playlist.artworkUrl, cornerRadius: 16, placeholderIcon: "music.note.list")
                .frame(width: 180, height: 180)
                .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 8)

            VStack(spacing: 4) {
                Text(playlist.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                let count = tracks.count > 0 ? tracks.count : playlist.trackCount
                Text("\(count) треков")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.amrTextSecondary)
            }
        }
    }

    // MARK: - Play / Shuffle Action Buttons

    private var actionButtonsView: some View {
        HStack(spacing: 12) {
            // Play All
            Button(action: {
                AMRHaptics.medium()
                store.playPlaylist(name: playlist.name, shuffle: false)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15))
                    Text("Воспроизвести")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .buttonStyle(AMRActionButtonStyle(backgroundColor: .amrRed))

            // Shuffle
            Button(action: {
                AMRHaptics.medium()
                store.playPlaylist(name: playlist.name, shuffle: true)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 15))
                    Text("Перемешать")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .buttonStyle(AMRActionButtonStyle(backgroundColor: .amrSurfaceGlass))
        }
    }


    // MARK: - Track Row (Independent sibling buttons, NO nested buttons)

    private func trackRow(track: TrackItem, index: Int) -> some View {
        let isCurrent = store.currentTrack?.id == track.id || (store.currentTrack?.name == track.name && store.currentTrack?.artist == track.artist)

        return HStack(spacing: 0) {
            // 1. Main Clickable Track Button
            Button(action: {
                AMRHaptics.light()
                let targetId = Int(track.id)
                store.playPlaylist(name: playlist.name, trackId: targetId, trackIndex: track.index ?? index, shuffle: false)
            }) {
                HStack(spacing: 12) {
                    // Index / Waveform
                    if isCurrent && store.playerState == .playing {
                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.amrRed)
                            .frame(width: 24, alignment: .center)
                    } else {
                        Text("\(index)")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(isCurrent ? .amrRed : .amrTextTertiary)
                            .frame(width: 24, alignment: .center)
                    }

                    // Track Artwork Thumbnail
                    RemoteImageView(urlString: track.artworkUrl, cornerRadius: 6, placeholderIcon: "music.note")
                        .frame(width: 42, height: 42)

                    // Title & Artist
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.name)
                            .font(.system(size: 15, weight: isCurrent ? .bold : .medium))
                            .foregroundColor(isCurrent ? .amrRed : .white)
                            .lineLimit(1)

                        Text(track.artist)
                            .font(.system(size: 12))
                            .foregroundColor(.amrTextSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    // Star if favorited
                    if track.isFavorited == true {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.yellow)
                    }
                }
                .padding(.vertical, 10)
                .padding(.leading, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 2. Independent More Menu Button (Sibling, NOT nested!)
            Button(action: {
                AMRHaptics.selection()
                selectedTrackForSheet = track
            }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.amrTextTertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isCurrent ? Color.amrRed.opacity(0.12) : Color.clear)
        )
        .swipeActions(edge: .trailing) {
            Button {
                store.queueAddToEnd(track)
            } label: {
                Label("В конец очереди", systemImage: "text.line.last.and.arrowtriangle.forward")
            }
            .tint(.blue)

            Button {
                store.queuePlayNext(track)
            } label: {
                Label("Играть следующим", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .tint(.purple)
        }
    }
}
