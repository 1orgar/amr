//
//  QueueView.swift
//  AppleMusicRemoteIOS
//
//  Interactive Playback Queue with Drag-and-Drop Reordering, Swipe Deletion,
//  Clear Queue, and Infinity Auto-Play toggle.
//

import SwiftUI

public struct QueueView: View {
    @ObservedObject var playerManager: PlayerManager
    @State private var showingClearConfirmation = false
    @State private var isAutoPlayEnabled = true
    
    public var body: some View {
        NavigationStack {
            List {
                // Section 1: Now Playing Live Card
                Section(header: Text("Сейчас играет").font(.system(size: 14, weight: .bold)).foregroundColor(.amrRed)) {
                    HStack(spacing: 14) {
                        AsyncImage(url: URL(string: playerManager.currentTrack.artworkUrl)) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color.gray.opacity(0.3)
                            }
                        }
                        .frame(width: 54, height: 54)
                        .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(playerManager.currentTrack.title)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            Text(playerManager.currentTrack.artist + " • " + playerManager.currentTrack.album)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(Color.white.opacity(0.6))
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        // Waveform Visualizer Badge
                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 1).fill(Color.amrRed).frame(width: 2.5, height: 14)
                            RoundedRectangle(cornerRadius: 1).fill(Color.amrRed).frame(width: 2.5, height: 20)
                            RoundedRectangle(cornerRadius: 1).fill(Color.amrRed).frame(width: 2.5, height: 10)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color(white: 0.16).opacity(0.85))
                
                // Section 2: Up Next Tracks with Native Reordering
                Section(header:
                    HStack {
                        Text("Далее: \(playerManager.queueSourceTitle)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button(action: {
                            AMRHaptics.buttonTap()
                            playerManager.toggleShuffle()
                        }) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(playerManager.isShuffle ? .amrRed : .white.opacity(0.6))
                        }
                    }
                ) {
                    ForEach(playerManager.queueTracks) { track in
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: track.artworkUrl)) { phase in
                                if let image = phase.image {
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    Color.gray.opacity(0.3)
                                }
                            }
                            .frame(width: 44, height: 44)
                            .cornerRadius(6)
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                
                                Text(track.artist)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(Color.white.opacity(0.5))
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                playerManager.presentActionSheet(for: track)
                            }) {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Color.white.opacity(0.5))
                                    .padding(6)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { sourceIndices, destinationIndex in
                        AMRHaptics.queueDrop()
                        playerManager.moveQueueItem(from: sourceIndices, to: destinationIndex)
                    }
                    .onDelete { indices in
                        AMRHaptics.warningAlert()
                        playerManager.removeQueueItem(at: indices)
                    }
                    .listRowBackground(Color(white: 0.10).opacity(0.65))
                }
                
                // Section 3: Auto-Play Toggle & Add Next
                Section {
                    Toggle(isOn: $isAutoPlayEnabled) {
                        HStack(spacing: 10) {
                            Image(systemName: "infinity")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.amrRed)
                            Text("Автовоспроизведение")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .tint(.amrRed)
                }
                .listRowBackground(Color(white: 0.12).opacity(0.5))
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Очередь")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Очистить") {
                        showingClearConfirmation = true
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.amrRed)
                    .disabled(playerManager.queueTracks.isEmpty)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                        .foregroundColor(.white)
                }
            }
            .confirmationDialog(
                "Очистить очередь воспроизведения?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Очистить все треки", role: .destructive) {
                    AMRHaptics.warningAlert()
                    playerManager.clearQueue()
                }
                Button("Отмена", role: .cancel) {}
            }
        }
    }
}
