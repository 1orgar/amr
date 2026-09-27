//
//  TrackActionSheet.swift
//  AppleMusicRemoteIOS
//
//  iOS 18 style bottom action sheet with Play Next, Add to Queue, Radio, Add to Library
//

import SwiftUI

public struct TrackActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let track: TrackItem
    @ObservedObject public var store: PlayerStore

    public init(track: TrackItem, store: PlayerStore = .shared) {
        self.track = track
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Header Preview
            HStack(spacing: 14) {
                RemoteImageView(urlString: track.artworkUrl, cornerRadius: 10, placeholderIcon: "music.note")
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(track.artist)
                        .font(.system(size: 14))
                        .foregroundColor(.amrTextSecondary)
                        .lineLimit(1)

                    if let album = track.album, !album.isEmpty {
                        Text(album)
                            .font(.system(size: 12))
                            .foregroundColor(.amrTextTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Divider().background(Color.amrBorderGlass)

            // Actions List
            VStack(spacing: 6) {
                // 1. Play Next
                ActionSheetRow(icon: "text.line.first.and.arrowtriangle.forward", title: "Играть следующим") {
                    store.queuePlayNext(track)
                    dismiss()
                }

                // 2. Add to Queue
                ActionSheetRow(icon: "text.badge.plus", title: "В конец очереди") {
                    store.queueAddToEnd(track)
                    dismiss()
                }

                // 3. Play Station
                ActionSheetRow(icon: "radio", title: "Запустить радио по треку") {
                    let station = StationItem(
                        id: "station_\(track.id)",
                        name: "Радио: \(track.name)",
                        subtitle: track.artist,
                        artworkUrl: track.artworkUrl,
                        url: "https://music.apple.com/station/ra.u-\(track.id)",
                        isLive: false,
                        color: nil
                    )
                    store.playStation(station)
                    dismiss()
                }

                // 4. Add to Local Library (for cloud tracks)
                if track.isLocal != true {
                    ActionSheetRow(icon: "plus.square.on.square", title: "Добавить в медиатеку Mac") {
                        store.addTrackToLibrary(track)
                        dismiss()
                    }
                }

                // 5. Favorite
                ActionSheetRow(icon: "star", title: "Добавить в избранное") {
                    store.toggleFavorite()
                    dismiss()
                }
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .presentationDetents([.fraction(0.52), .large])
        .presentationDragIndicator(.visible)
        .background(Color.amrBackground)
    }
}

private struct ActionSheetRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.amrRed)
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)

                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color.amrSurfaceGlass)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
