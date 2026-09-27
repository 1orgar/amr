//
//  NowPlayingView.swift
//  AppleMusicRemoteIOS
//
//  Pixel-perfect Apple Music player with ambient artwork glow, Lossless badge,
//  custom responsive timeline scrubber, transport controls, and volume
//

import SwiftUI

public struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var store: PlayerStore

    @State private var isScrubbing: Bool = false
    @State private var scrubPosition: Double = 0.0
    @State private var isDraggingVolume: Bool = false
    @State private var dragVolume: Double = 0.0
    @State private var showActionSheet: Bool = false

    public init(store: PlayerStore = .shared) {
        self.store = store
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // 1. Dynamic Ambient Blurred Artwork Background (strictly bounded to screen size)
                ambientBackground(width: geo.size.width, height: geo.size.height)

                // 2. Main Player Content
                VStack(spacing: 0) {
                    // Top drag grabber
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 36, height: 5)
                        .padding(.top, 10)

                    Spacer(minLength: 8)

                    // Album Artwork
                    let artSize = min(geo.size.width - 64, max(geo.size.height * 0.34, 180))
                    artworkView(size: artSize)

                    Spacer(minLength: 12)

                    // Track Title, Artist, and Favorite
                    trackMetaView
                        .padding(.horizontal, 28)

                    // Lossless Audio Quality Badge
                    losslessBadgeView
                        .padding(.top, 6)

                    Spacer(minLength: 10)

                    // Timeline Scrubber
                    customTimelineView
                        .padding(.horizontal, 28)

                    Spacer(minLength: 10)

                    // Transport Controls (Shuffle, Prev, Play/Pause, Next, Options)
                    transportControlsView
                        .padding(.horizontal, 24)

                    Spacer(minLength: 12)

                    // Volume Controls
                    customVolumeView
                        .padding(.horizontal, 28)

                    Spacer(minLength: 10)

                    // Bottom Route / Server Info
                    bottomRouteBar
                        .padding(.horizontal, 30)
                        .padding(.bottom, 10)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .sheet(isPresented: $showActionSheet) {
            if let trk = store.currentTrack {
                TrackActionSheet(track: trk, store: store)
            }
        }
    }

    // MARK: - Ambient Background

    private func ambientBackground(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.amrBackground

            if let artUrl = store.currentTrack?.artworkUrl, !artUrl.isEmpty {
                RemoteImageView(urlString: artUrl, cornerRadius: 0)
                    .frame(width: width, height: height)
                    .blur(radius: 70)
                    .opacity(0.45)
                    .clipped()
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.2),
                    Color.black.opacity(0.65),
                    Color.black.opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(width: width, height: height)
        .clipped()
        .ignoresSafeArea()
    }

    // MARK: - Artwork View

    private func artworkView(size: CGFloat) -> some View {
        RemoteImageView(
            urlString: store.currentTrack?.artworkUrl,
            cornerRadius: 16,
            placeholderIcon: "music.note"
        )
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.45), radius: 20, x: 0, y: 10)
        .scaleEffect(store.playerState == .playing ? 1.0 : 0.9)
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: store.playerState)
    }

    // MARK: - Track Title & Artist

    private var trackMetaView: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.currentTrack?.name ?? "Не воспроизводится")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(store.currentTrack?.artist ?? "Apple Music Remote")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.amrTextSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: {
                AMRHaptics.medium()
                store.toggleFavorite()
            }) {
                Image(systemName: store.currentTrack?.isFavorited == true ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(store.currentTrack?.isFavorited == true ? .yellow : .white.opacity(0.55))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Audio Quality Badge

    private var losslessBadgeView: some View {
        let q = store.audioQuality.lowercased()
        let icon: String = {
            if q.contains("lossless") { return "waveform.badge.magnifyingglass" }
            if q.contains("atmos") || q.contains("dolby") { return "dot.radiowaves.left.and.right" }
            return "waveform"
        }()

        return HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(store.audioQuality)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundColor(.amrTextTertiary)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    // MARK: - Custom Apple Music Scrubber Timeline

    private var customTimelineView: some View {
        let currentPos = isScrubbing ? scrubPosition : store.position
        let maxDur = max(store.duration, 1.0)
        let progress = CGFloat(min(max(currentPos / maxDur, 0.0), 1.0))

        return VStack(spacing: 6) {
            GeometryReader { barGeo in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 4)

                    // Filled progress
                    Capsule()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: max(barGeo.size.width * progress, 0), height: 4)

                    // Scrubber thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: isScrubbing ? 14 : 8, height: isScrubbing ? 14 : 8)
                        .offset(x: max(0, min(barGeo.size.width * progress - (isScrubbing ? 7 : 4), barGeo.size.width - (isScrubbing ? 14 : 8))))
                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                        .animation(.easeOut(duration: 0.1), value: isScrubbing)
                }
                .frame(height: 16)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            let boundedX = min(max(0, value.location.x), barGeo.size.width)
                            let newFraction = Double(boundedX / barGeo.size.width)
                            scrubPosition = newFraction * maxDur
                        }
                        .onEnded { value in
                            let boundedX = min(max(0, value.location.x), barGeo.size.width)
                            let newFraction = Double(boundedX / barGeo.size.width)
                            let target = newFraction * maxDur
                            store.seek(to: target)
                            scrubPosition = target
                            isScrubbing = false
                        }
                )
            }
            .frame(height: 16)

            // Timestamps
            HStack {
                Text(formatTime(currentPos))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.amrTextTertiary)

                Spacer()

                let remaining = max(0, store.duration - currentPos)
                Text("-\(formatTime(remaining))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.amrTextTertiary)
            }
        }
    }

    // MARK: - Transport Controls

    private var transportControlsView: some View {
        HStack {
            Spacer()

            // Previous
            Button(action: {
                AMRHaptics.light()
                store.previousTrack()
            }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)

            Spacer()

            // Play / Pause
            Button(action: {
                AMRHaptics.medium()
                store.togglePlayPause()
            }) {
                Image(systemName: store.playerState == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white)
                    .frame(width: 68, height: 68)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.14))
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            // Next
            Button(action: {
                AMRHaptics.light()
                store.nextTrack()
            }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Custom Volume View

    private var customVolumeView: some View {
        let currentVol = isDraggingVolume ? dragVolume : store.volume
        let volFraction = CGFloat(max(0, min(100, currentVol)) / 100.0)

        return HStack(spacing: 12) {
            Button(action: {
                AMRHaptics.selection()
                store.toggleMute()
            }) {
                Image(systemName: store.isMuted || currentVol == 0 ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.amrTextSecondary)
                    .frame(width: 22, height: 36)
            }
            .buttonStyle(.plain)

            GeometryReader { volGeo in
                ZStack(alignment: .leading) {
                    // Expanded touch hit area
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 36)

                    // Background track
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 4)

                    // Active progress
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: max(volGeo.size.width * volFraction, 0), height: 4)

                    // Thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: isDraggingVolume ? 14 : 10, height: isDraggingVolume ? 14 : 10)
                        .offset(x: max(0, min(volGeo.size.width * volFraction - (isDraggingVolume ? 7 : 5), volGeo.size.width - (isDraggingVolume ? 14 : 10))))
                        .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 1)
                        .animation(.easeOut(duration: 0.1), value: isDraggingVolume)
                }
                .frame(height: 36)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDraggingVolume {
                                isDraggingVolume = true
                                store.isDraggingVolume = true
                            }
                            let boundedX = min(max(0, value.location.x), volGeo.size.width)
                            let newVol = (volGeo.size.width > 0) ? (Double(boundedX / volGeo.size.width) * 100.0) : 0.0
                            dragVolume = newVol
                            store.setVolumeThrottled(newVol)
                        }
                        .onEnded { value in
                            let boundedX = min(max(0, value.location.x), volGeo.size.width)
                            let finalVol = (volGeo.size.width > 0) ? (Double(boundedX / volGeo.size.width) * 100.0) : 0.0
                            dragVolume = finalVol
                            store.setVolume(finalVol)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                isDraggingVolume = false
                                store.isDraggingVolume = false
                            }
                        }
                )
            }
            .frame(height: 36)

            Button(action: {
                AMRHaptics.selection()
                store.setVolume(100.0)
            }) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.amrTextSecondary)
                    .frame(width: 22, height: 36)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Bottom Route / Server Bar

    private var bottomRouteBar: some View {
        HStack {
            Button(action: {
                AMRHaptics.selection()
                store.showDiscoverySheet = true
            }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(store.isConnected ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                    Image(systemName: "macbook.and.iphone")
                        .font(.system(size: 12))
                    Text(store.isConnected ? (store.currentServer?.name ?? "Mac") : "Нет подключения")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(store.isConnected ? .amrTextSecondary : .amrRed)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: {
                AMRHaptics.selection()
                store.selectedTab = 4
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 13, weight: .semibold))
                    Text(store.currentPlaylistName.isEmpty ? "Очередь" : store.currentPlaylistName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(.amrRed)
            }
            .buttonStyle(.plain)
        }
    }

    private func formatTime(_ sec: Double) -> String {
        let mins = Int(sec) / 60
        let secs = Int(sec) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
