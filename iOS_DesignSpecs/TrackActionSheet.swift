//
//  TrackActionSheet.swift
//  AppleMusicRemoteIOS
//
//  Universal Track Context Action Sheet with Track Header, Play Next,
//  Add to Queue, Station from Track, Add to Library, and Favorite Toggles.
//

import SwiftUI

public struct TrackActionSheet: View {
    let track: TrackItem
    @ObservedObject var playerManager: PlayerManager
    @Environment(\.dismiss) private var dismiss
    
    public var body: some View {
        VStack(spacing: 0) {
            // Track Preview Header
            HStack(spacing: 16) {
                AsyncImage(url: URL(string: track.artworkUrl)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
                .frame(width: 58, height: 58)
                .cornerRadius(10)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(track.artist + " — " + track.album)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.7))
                        .lineLimit(1)
                    
                    // Audio Format Tag
                    Text("ALAC Lossless 24-bit/48kHz")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.amrRed)
                }
                
                Spacer()
            }
            .padding(20)
            .background(.ultraThinMaterial)
            
            Divider().background(Color.white.opacity(0.1))
            
            // Action Menu List
            ScrollView {
                VStack(spacing: 2) {
                    ActionSheetButton(
                        icon: "text.line.first.and.arrowtriangle.forward",
                        title: "Играть следующим",
                        subtitle: "Поставить сразу после текущего трека"
                    ) {
                        AMRHaptics.buttonTap()
                        playerManager.playNext(track: track)
                        dismiss()
                    }
                    
                    ActionSheetButton(
                        icon: "text.badge.plus",
                        title: "В конец очереди",
                        subtitle: "Добавить трек в Up Next"
                    ) {
                        AMRHaptics.buttonTap()
                        playerManager.addToQueue(track: track)
                        dismiss()
                    }
                    
                    ActionSheetButton(
                        icon: "dot.radiowaves.left.and.right",
                        title: "Создать станцию по треку",
                        subtitle: "Бесконечное радио на основе песни"
                    ) {
                        AMRHaptics.playPauseToggle()
                        playerManager.startStation(from: track)
                        dismiss()
                    }
                    
                    ActionSheetButton(
                        icon: track.isInLibrary ? "trash" : "plus.circle",
                        title: track.isInLibrary ? "Удалить из медиатеки" : "Добавить в медиатеку Mac",
                        subtitle: "Синхронизация с локальной коллекцией",
                        isDestructive: track.isInLibrary
                    ) {
                        AMRHaptics.buttonTap()
                        playerManager.toggleLibrary(for: track)
                        dismiss()
                    }
                    
                    ActionSheetButton(
                        icon: track.isFavorited ? "star.slash" : "star.fill",
                        title: track.isFavorited ? "Удалить из избранного" : "В избранное",
                        subtitle: "Отметить трек звездочкой",
                        iconColor: .amrRed
                    ) {
                        AMRHaptics.favoriteSuccess()
                        playerManager.toggleFavorite(for: track)
                        dismiss()
                    }
                    
                    ActionSheetButton(
                        icon: "square.and.arrow.up",
                        title: "Поделиться треком...",
                        subtitle: "Скопировать ссылку Apple Music"
                    ) {
                        AMRHaptics.buttonTap()
                        playerManager.shareTrack(track: track)
                        dismiss()
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(Color(hex: "#121214").ignoresSafeArea())
    }
}

// MARK: - Action Sheet Button Component
public struct ActionSheetButton: View {
    let icon: String
    let title: String
    let subtitle: String
    var iconColor: Color = .white
    var isDestructive: Bool = false
    let action: () -> Void
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isDestructive ? .amrError : iconColor)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isDestructive ? .amrError : .white)
                    
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.45))
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
