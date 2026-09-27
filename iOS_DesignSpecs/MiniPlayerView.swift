//
//  MiniPlayerView.swift
//  AppleMusicRemoteIOS
//
//  Floating Translucent Mini-Player docking above the TabBar with interactive
//  gesture expansion to the Full Screen Now Playing sheet.
//

import SwiftUI

public struct MiniPlayerView: View {
    @ObservedObject var playerManager: PlayerManager
    let onExpand: () -> Void
    
    public var body: some View {
        Button(action: onExpand) {
            ZStack(alignment: .bottom) {
                // Glassmorphism background with hairline top border
                HStack(spacing: 12) {
                    // Artwork with subtle shadow
                    AsyncImage(url: URL(string: playerManager.currentTrack.artworkUrl)) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.gray.opacity(0.3)
                        }
                    }
                    .frame(width: 42, height: 42)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                    
                    // Track Title & Artist
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playerManager.currentTrack.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(playerManager.currentTrack.artist)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Controls: Play/Pause & Skip Next
                    HStack(spacing: 18) {
                        Button(action: {
                            AMRHaptics.playPauseToggle()
                            playerManager.togglePlayPause()
                        }) {
                            Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            AMRHaptics.trackSkip()
                            playerManager.nextTrack()
                        }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(.ultraThinMaterial)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                
                // Mini Progress Line Indicator
                GeometryReader { geo in
                    let progress = playerManager.currentTrack.duration > 0 ? (playerManager.playbackPosition / playerManager.currentTrack.duration) : 0
                    Rectangle()
                        .fill(Color.amrRed)
                        .frame(width: max(0, min(geo.size.width * CGFloat(progress), geo.size.width)), height: 2.5)
                }
                .frame(height: 2.5)
                .padding(.horizontal, 14)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }
}
