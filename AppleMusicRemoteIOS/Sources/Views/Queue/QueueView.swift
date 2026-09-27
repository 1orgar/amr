//
//  QueueView.swift
//  AppleMusicRemoteIOS
//
//  Up Next queue with drag reordering, swipe to delete, swipe to play next, and clear queue actions
//

import SwiftUI

public enum QueueTab: String, CaseIterable, Identifiable {
    case upcoming = "Очередь"
    case history = "История"
    public var id: String { rawValue }
}

public struct QueueView: View {
    @ObservedObject public var store: PlayerStore

    @State private var selectedTab: QueueTab = .upcoming
    @State private var showClearConfirmation: Bool = false
    @State private var selectedTrack: TrackItem?

    public init(store: PlayerStore = .shared) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented Picker for Queue / History
                Picker("Раздел", selection: $selectedTab) {
                    ForEach(QueueTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)

                List {
                    if selectedTab == .upcoming {
                        // Section 1: Now Playing
                        if let cur = store.currentTrack {
                            Section(header: Text("СЕЙЧАС ИГРАЕТ").font(.system(size: 12, weight: .bold)).foregroundColor(.amrTextTertiary)) {
                                HStack(spacing: 12) {
                                    RemoteImageView(urlString: cur.artworkUrl, cornerRadius: 8, placeholderIcon: "waveform")
                                        .frame(width: 48, height: 48)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(cur.name)
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text(cur.artist)
                                            .font(.system(size: 13))
                                            .foregroundColor(.amrTextSecondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Image(systemName: "waveform")
                                        .foregroundColor(.amrRed)
                                        .font(.system(size: 16, weight: .bold))
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color.amrRed.opacity(0.12))
                        }

                        // Section 2: Up Next
                        Section(
                            header: HStack {
                                Text("ДАЛЕЕ В ОЧЕРЕДИ (\(store.upcomingTracks.count))")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.amrTextTertiary)
                                Spacer()
                                if !store.upcomingTracks.isEmpty {
                                    Button("Очистить") {
                                        showClearConfirmation = true
                                    }
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.amrRed)
                                }
                            }
                        ) {
                            if store.upcomingTracks.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "list.bullet.rectangle")
                                        .font(.system(size: 32))
                                        .foregroundColor(.amrTextTertiary)
                                    Text("Очередь пуста")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.amrTextSecondary)
                                    Text("Добавьте треки из плейлистов или поиска")
                                        .font(.system(size: 13))
                                        .foregroundColor(.amrTextTertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                            } else {
                                ForEach(Array(store.upcomingTracks.enumerated()), id: \.element.id) { index, track in
                                    Button(action: {
                                        store.queuePlayIndex(index)
                                    }) {
                                        HStack(spacing: 12) {
                                            Text("\(index + 1)")
                                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                                .foregroundColor(.amrTextTertiary)
                                                .frame(width: 24, alignment: .leading)

                                            RemoteImageView(urlString: track.artworkUrl, cornerRadius: 6, placeholderIcon: "music.note")
                                                .frame(width: 40, height: 40)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(track.name)
                                                    .font(.system(size: 15, weight: .medium))
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                Text(track.artist)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.amrTextSecondary)
                                                    .lineLimit(1)
                                            }

                                            Spacer()

                                            Image(systemName: "play.circle")
                                                .font(.system(size: 18))
                                                .foregroundColor(.amrTextSecondary)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            store.queueRemove(at: index)
                                        } label: {
                                            Label("Удалить", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            store.queuePlayNext(track)
                                        } label: {
                                            Label("Следующий", systemImage: "text.line.first.and.arrowtriangle.forward")
                                        }
                                        .tint(.purple)
                                    }
                                }
                                .onDelete { indexSet in
                                    for idx in indexSet {
                                        store.queueRemove(at: idx)
                                    }
                                }
                            }
                        }
                        .listRowBackground(Color.amrSurfaceGlass)
                    } else {
                        // Section: History
                        Section(
                            header: HStack {
                                Text("ИСТОРИЯ ВОСПРОИЗВЕДЕНИЯ (\(store.historyTracks.count))")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.amrTextTertiary)
                                Spacer()
                            }
                        ) {
                            if store.historyTracks.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 32))
                                        .foregroundColor(.amrTextTertiary)
                                    Text("История пуста")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.amrTextSecondary)
                                    Text("Здесь появятся недавно сыгранные треки")
                                        .font(.system(size: 13))
                                        .foregroundColor(.amrTextTertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                            } else {
                                ForEach(Array(store.historyTracks.enumerated()), id: \.element.id) { index, track in
                                    Button(action: {
                                        store.playHistoryTrack(track)
                                    }) {
                                        HStack(spacing: 12) {
                                            Text("\(index + 1)")
                                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                                .foregroundColor(.amrTextTertiary)
                                                .frame(width: 24, alignment: .leading)

                                            RemoteImageView(urlString: track.artworkUrl, cornerRadius: 6, placeholderIcon: "music.note")
                                                .frame(width: 40, height: 40)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(track.name)
                                                    .font(.system(size: 15, weight: .medium))
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                Text(track.artist)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.amrTextSecondary)
                                                    .lineLimit(1)
                                            }

                                            Spacer()

                                            Image(systemName: "play.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundColor(.amrRed)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .listRowBackground(Color.amrSurfaceGlass)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(Color.amrBackground.ignoresSafeArea())
            .navigationTitle(selectedTab == .upcoming ? "Очередь" : "История")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        AMRHaptics.selection()
                        store.loadQueue()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.amrRed)
                    }
                }
            }
            .confirmationDialog("Очистить очередь воспроизведения?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
                Button("Очистить очередь", role: .destructive) {
                    store.queueClear()
                }
                Button("Отмена", role: .cancel) {}
            }
            .onAppear {
                store.loadQueue()
            }
        }
    }
}
