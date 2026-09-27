//
//  StationsView.swift
//  AppleMusicRemoteIOS
//
//  Apple Music Stations: Curated For You, Live Apple Music 1, and Genre Radio
//

import SwiftUI

public struct StationsView: View {
    @ObservedObject public var store: PlayerStore

    private let countries = [
        ("ru", "🇷🇺 Россия"),
        ("us", "🇺🇸 США"),
        ("gb", "🇬🇧 Великобритания"),
        ("de", "🇩🇪 Германия"),
        ("kz", "🇰🇿 Казахстан")
    ]

    public init(store: PlayerStore = .shared) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    // Country / Region Selector in top header
                    regionSelectorView

                    // 1. «Для вас» Section (Personal & Discovery)
                    personalStationsSection

                    // 2. «Топ-чарт Apple Music» (MusicKit)
                    if !store.topChartSongs.isEmpty {
                        topChartsSection
                    }

                    // 3. «Прямой эфир» Live Stations (Apple Music 1, Hits, Country)
                    liveStationsSection

                    // 4. «Жанровые станции» (Chill, Pop, Rock, Hip-Hop, Dance, Deep House, Jazz)
                    genreStationsSection
                }
                .padding(.vertical, 16)
            }
            .background(Color.amrBackground.ignoresSafeArea())
            .navigationTitle("Радио")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { store.showDiscoverySheet = true }) {
                        Image(systemName: "macbook.and.iphone")
                            .foregroundColor(.amrRed)
                    }
                }
            }
            .onAppear {
                store.loadStations()
                store.loadTopCharts()
            }
        }
    }

    // MARK: - Sections

    private var regionSelectorView: some View {
        HStack {
            Text("РЕГИОН КАТАЛОГА")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.amrTextTertiary)

            Spacer()

            Menu {
                ForEach(countries, id: \.0) { item in
                    Button(item.1) {
                        store.selectedCountry = item.0
                        store.loadStations()
                        store.loadTopCharts()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(countries.first(where: { $0.0 == store.selectedCountry })?.1 ?? "Россия")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundColor(.amrRed)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.amrRed.opacity(0.12)))
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Top Charts Section (MusicKit)

    private var topChartsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ТОП-ЧАРТ")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.amrRed)
                    Text("Популярно в Apple Music")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                Spacer()
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.amrRed)
                    .font(.system(size: 16, weight: .semibold))
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(store.topChartSongs.prefix(15).enumerated()), id: \.element.id) { idx, track in
                        Button(action: {
                            store.playCloudTrack(track)
                        }) {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack(alignment: .bottomLeading) {
                                    RemoteImageView(urlString: track.artworkUrl, cornerRadius: 10, placeholderIcon: "music.note")
                                        .frame(width: 140, height: 140)

                                    // Rank Badge
                                    Text("\(idx + 1)")
                                        .font(.system(size: 14, weight: .black, design: .rounded))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.75))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .padding(6)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text(track.artist)
                                        .font(.system(size: 12))
                                        .foregroundColor(.amrTextSecondary)
                                        .lineLimit(1)
                                }
                                .frame(width: 140, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var personalStationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Для вас")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    let personal = store.curatedStations.filter { $0.id == "station_personal" || $0.id == "station_discovery" }
                    if personal.isEmpty {
                        // Fallback hero cards
                        HeroStationCard(
                            title: "Моя станция",
                            subtitle: "Любимые треки и рекомендации",
                            colors: [Color(hex: "#FA2D48"), Color(hex: "#FF6B8B")],
                            icon: "sparkles"
                        ) {
                            let item = StationItem(
                                id: "station_personal",
                                name: "Моя станция",
                                subtitle: "Персональное радио",
                                artworkUrl: nil,
                                url: "https://music.apple.com/station/my-station/ra.u-personal",
                                isLive: false,
                                color: nil
                            )
                            store.playStation(item)
                        }

                        HeroStationCard(
                            title: "Станция открытий",
                            subtitle: "Новая музыка по вашему вкусу",
                            colors: [Color(hex: "#7928CA"), Color(hex: "#FF0080")],
                            icon: "waveform.badge.plus"
                        ) {
                            let item = StationItem(
                                id: "station_discovery",
                                name: "Станция открытий",
                                subtitle: "Discovery Station",
                                artworkUrl: nil,
                                url: "https://music.apple.com/station/discovery-station/ra.u-discovery",
                                isLive: false,
                                color: nil
                            )
                            store.playStation(item)
                        }
                    } else {
                        ForEach(personal) { item in
                            StationCardView(station: item) {
                                store.playStation(item)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var liveStationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Прямой эфир")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                // LIVE Pulsing Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.red.opacity(0.85)))
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    let liveList = store.curatedStations.filter { $0.isLive == true }
                    if liveList.isEmpty {
                        LiveStationTile(title: "Apple Music 1", subtitle: "LA & London Live", icon: "antenna.radiowaves.left.and.right") {
                            let s = StationItem(
                                id: "station_am1",
                                name: "Apple Music 1 Live",
                                subtitle: "Прямой эфир",
                                artworkUrl: nil,
                                url: "https://music.apple.com/station/apple-music-1/ra.985484166",
                                isLive: true,
                                color: nil
                            )
                            store.playStation(s)
                        }
                    } else {
                        ForEach(liveList) { item in
                            StationCardView(station: item) {
                                store.playStation(item)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var genreStationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Жанровые станции")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 20)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                let genres = store.curatedStations.filter { $0.isLive != true && $0.id != "station_personal" && $0.id != "station_discovery" }
                ForEach(genres) { station in
                    StationCardView(station: station) {
                        store.playStation(station)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Station Cards

private struct HeroStationCard: View {
    let title: String
    let subtitle: String
    let colors: [Color]
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .padding(16)
            .frame(width: 220, height: 140)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: colors.first?.opacity(0.35) ?? .clear, radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private struct LiveStationTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(.amrRed)
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }

                Spacer()

                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.amrTextSecondary)
            }
            .padding(14)
            .frame(width: 170, height: 120)
            .amrDarkGlass(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }
}

private struct StationCardView: View {
    let station: StationItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                // Cover
                ZStack(alignment: .bottomTrailing) {
                    RemoteImageView(urlString: station.artworkUrl, cornerRadius: 14, placeholderIcon: "radio")
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Play badge
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(7)
                        .background(Circle().fill(Color.black.opacity(0.65)))
                        .padding(8)
                }

                Text(station.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let sub = station.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundColor(.amrTextSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
