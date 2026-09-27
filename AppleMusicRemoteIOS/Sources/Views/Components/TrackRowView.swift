//
//  TrackRowView.swift
//  AppleMusicRemoteIOS
//
//  Interactive track row component with cover art, status indicator, and ⋯ action menu
//

import SwiftUI

public struct TrackRowView: View {
    public let track: TrackItem
    public let index: Int?
    public let isCurrent: Bool
    public let onPlay: () -> Void
    public let onMore: () -> Void

    public init(
        track: TrackItem,
        index: Int? = nil,
        isCurrent: Bool = false,
        onPlay: @escaping () -> Void,
        onMore: @escaping () -> Void
    ) {
        self.track = track
        self.index = index
        self.isCurrent = isCurrent
        self.onPlay = onPlay
        self.onMore = onMore
    }

    public var body: some View {
        HStack(spacing: 0) {
            // 1. Clickable Track Info Row
            Button(action: {
                AMRHaptics.light()
                onPlay()
            }) {
                HStack(spacing: 12) {
                    // Index or Equalizer indicator
                    if isCurrent {
                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.amrRed)
                            .frame(width: 24)
                    } else if let idx = index {
                        Text("\(idx)")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(.amrTextTertiary)
                            .frame(width: 24, alignment: .center)
                    }

                    // Artwork
                    RemoteImageView(urlString: track.artworkUrl, cornerRadius: 8, placeholderIcon: "music.note")
                        .frame(width: 44, height: 44)

                    // Track Info
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.name)
                            .font(.system(size: 16, weight: isCurrent ? .bold : .medium))
                            .foregroundColor(isCurrent ? .amrRed : .white)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Text(track.artist)
                            if let album = track.album, !album.isEmpty {
                                Text("•")
                                Text(album)
                            }
                        }
                        .font(.system(size: 13))
                        .foregroundColor(.amrTextSecondary)
                        .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    // Duration if available
                    if track.duration > 0 {
                        Text(formatDuration(track.duration))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.amrTextTertiary)
                    }
                }
                .padding(.vertical, 8)
                .padding(.leading, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 2. Independent ⋯ Action Button (Sibling, NOT nested!)
            Button(action: {
                AMRHaptics.selection()
                onMore()
            }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.amrTextSecondary)
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
        }
        .background(isCurrent ? Color.amrRed.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func formatDuration(_ sec: Double) -> String {
        let mins = Int(sec) / 60
        let secs = Int(sec) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
