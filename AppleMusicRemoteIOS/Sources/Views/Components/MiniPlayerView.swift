//
//  MiniPlayerView.swift
//  AppleMusicRemoteIOS
//
//  Floating glass mini player docked above bottom tab bar
//

import SwiftUI

public struct MiniPlayerView: View {
    @ObservedObject public var store: PlayerStore
    public let onExpand: () -> Void

    public init(store: PlayerStore = .shared, onExpand: @escaping () -> Void) {
        self.store = store
        self.onExpand = onExpand
    }

    public var body: some View {
        HStack(spacing: 10) {
            // Clickable info section that expands full player
            Button(action: onExpand) {
                HStack(spacing: 12) {
                    // Cover
                    RemoteImageView(urlString: store.currentTrack?.artworkUrl, cornerRadius: 8, placeholderIcon: "music.note")
                        .frame(width: 42, height: 42)

                    // Title & Artist
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(store.isConnected ? Color.green : Color.red)
                                .frame(width: 6, height: 6)

                            Text(store.currentTrack?.name ?? (store.isConnected ? "Не воспроизводится" : "Нет подключения"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }

                        Text(store.currentTrack?.artist ?? (store.isConnected ? (store.currentServer?.name ?? "Подключено к Mac") : "Поиск Mac..."))
                            .font(.system(size: 13))
                            .foregroundColor(.amrTextSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(AMRButtonStyle())

            // Sibling Independent Play/Pause Button
            Button(action: {
                store.togglePlayPause()
            }) {
                Image(systemName: store.playerState == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.14)))
                    .contentShape(Circle())
            }
            .buttonStyle(AMRButtonStyle())

            // Sibling Independent Next Button
            Button(action: {
                store.nextTrack()
            }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.amrTextSecondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(AMRButtonStyle())

        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .amrDarkGlass(cornerRadius: 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}
