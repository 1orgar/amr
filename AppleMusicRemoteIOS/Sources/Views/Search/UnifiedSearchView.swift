//
//  UnifiedSearchView.swift
//  AppleMusicRemoteIOS
//
//  Tri-Scope Search across Local Library and Apple Music Cloud with Add to Library
//

import SwiftUI

public struct UnifiedSearchView: View {
    @ObservedObject public var store: PlayerStore

    @State private var query: String = ""
    @State private var selectedScope: String = "all"
    @State private var selectedTrack: TrackItem?

    public init(store: PlayerStore = .shared) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Scope Filter
                Picker("Поиск", selection: $selectedScope) {
                    Text("Все").tag("all")
                    Text("Медиатека").tag("library")
                    Text("Apple Music").tag("cloud")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .onChange(of: selectedScope) { _, newScope in
                    store.performSearch(query: query, scope: newScope)
                }

                // Results or Empty State
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    emptySearchState
                } else if store.isSearching {
                    VStack(spacing: 12) {
                        ProgressView().tint(.amrRed)
                        Text("Поиск в каталоге...").foregroundColor(.amrTextSecondary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    searchResultsList
                }
            }
            .background(Color.amrBackground.ignoresSafeArea())
            .navigationTitle("Поиск")
            .searchable(text: $query, prompt: "Артисты, песни, альбомы...")
            .onChange(of: query) { _, newQuery in
                store.performSearch(query: newQuery, scope: selectedScope)
            }
            .sheet(item: $selectedTrack) { trk in
                TrackActionSheet(track: trk, store: store)
            }
        }
    }

    // MARK: - Subviews

    private var emptySearchState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.amrRed.opacity(0.8))

            Text("Поиск по медиатеке и Apple Music")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Text("Введите название песни, исполнителя или альбома для мгновенного воспроизведения на Mac")
                .font(.system(size: 14))
                .foregroundColor(.amrTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                // 1. Artists
                if !store.searchResultsArtists.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("АРТИСТЫ")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.amrTextTertiary)
                            .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(store.searchResultsArtists) { art in
                                    Button(action: {
                                        query = art.name
                                        store.performSearch(query: art.name, scope: selectedScope)
                                    }) {
                                        VStack(spacing: 6) {
                                            Circle()
                                                .fill(Color.amrSurfaceGlass)
                                                .frame(width: 68, height: 68)
                                                .overlay(Image(systemName: "person.fill").font(.system(size: 24)).foregroundColor(.amrTextSecondary))

                                            Text(art.name)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                                .frame(width: 80)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }

                // 2. Songs
                if !store.searchResultsTracks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ПЕСНИ")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.amrTextTertiary)
                            .padding(.horizontal, 16)

                        ForEach(store.searchResultsTracks) { track in
                            TrackRowView(
                                track: track,
                                onPlay: {
                                    if track.isLocal == true, let id = Int(track.id) {
                                        store.playPlaylist(name: "Музыка", trackId: id)
                                    } else {
                                        store.playCloudTrack(track)
                                    }
                                },
                                onMore: {
                                    selectedTrack = track
                                }
                            )
                            .padding(.horizontal, 8)
                        }
                    }
                }

                if store.searchResultsTracks.isEmpty && store.searchResultsArtists.isEmpty {
                    Text("Ничего не найдено по запросу «\(query)»")
                        .foregroundColor(.amrTextSecondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                }
            }
            .padding(.vertical, 12)
        }
    }
}
