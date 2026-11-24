//
//  LibraryService+ArtistsAndAlbums.swift
//  AppleMusicRemoteMac
//
//  Local library artist & album aggregation, artist detail views, and recent items.
//

import Foundation

extension LibraryService {

    // MARK: - Artists & Albums

    public static func normalizedArtistName(_ raw: String) -> String {
        raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func artistMatchesLibraryTarget(trackArtist: String, targetArtist: String) -> Bool {
        let normTrack = normalizedArtistName(trackArtist)
        let normTarget = normalizedArtistName(targetArtist)
        guard !normTrack.isEmpty, !normTarget.isEmpty else { return false }
        if normTrack == normTarget {
            return true
        }

        // Tokenize strictly on collaboration boundaries so e.g. "Queen" never matches "Queens of the Stone Age".
        var parts = [trackArtist]
        let delimiters = [",", " & ", " feat. ", " feat ", " ft. ", " ft ", " with ", " / ", "; "]
        for sep in delimiters {
            var next: [String] = []
            for p in parts {
                var startIdx = p.startIndex
                while let range = p.range(of: sep, options: .caseInsensitive, range: startIdx..<p.endIndex) {
                    next.append(String(p[startIdx..<range.lowerBound]))
                    startIdx = range.upperBound
                }
                next.append(String(p[startIdx..<p.endIndex]))
            }
            parts = next
        }

        for token in parts {
            if normalizedArtistName(token) == normTarget {
                return true
            }
        }
        return false
    }

    public func getLibraryArtists(forceRefresh: Bool = false) -> [ArtistInfo] {
        let songs = getLibrarySongs(forceRefresh: forceRefresh)

        struct ArtistBucket {
            var name: String
            var trackCount: Int
            var distinctAlbums: Set<String>
            var artwork: String
        }

        var buckets: [String: ArtistBucket] = [:]

        for t in songs {
            let artist = t.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !artist.isEmpty, isValidTrack(name: t.name, artist: artist, duration: t.duration) else { continue }
            let key = Self.normalizedArtistName(artist)
            guard !key.isEmpty else { continue }

            let normAlb = MusicKitManager.normalizedAlbumTitle(t.album)
            let art = t.artworkUrl.trimmingCharacters(in: .whitespacesAndNewlines)

            if var existing = buckets[key] {
                existing.trackCount += 1
                if !normAlb.isEmpty {
                    existing.distinctAlbums.insert(normAlb)
                }
                if existing.artwork.isEmpty && !art.isEmpty {
                    existing.artwork = art
                } else if !existing.artwork.hasPrefix("http") && art.hasPrefix("http") {
                    existing.artwork = art
                }
                buckets[key] = existing
            } else {
                var albumsSet = Set<String>()
                if !normAlb.isEmpty {
                    albumsSet.insert(normAlb)
                }
                buckets[key] = ArtistBucket(
                    name: artist,
                    trackCount: 1,
                    distinctAlbums: albumsSet,
                    artwork: art
                )
            }
        }

        let result = buckets.values.map { b in
            ArtistInfo(
                name: b.name,
                trackCount: b.trackCount,
                albumCount: b.distinctAlbums.count,
                artwork: b.artwork.isEmpty ? nil : b.artwork
            )
        }

        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func getLibraryArtistDetail(artist: String) -> ArtistLibraryDetailResponse {
        let cleanTarget = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTarget.isEmpty else {
            return ArtistLibraryDetailResponse(artist: "", trackCount: 0, albumCount: 0, albums: [], songs: [])
        }

        let songs = getLibrarySongs()
        let normTarget = Self.normalizedArtistName(cleanTarget)
        var canonicalName = cleanTarget
        var foundExactCasing = false
        var matchedSongs: [TrackInfo] = []

        for s in songs {
            if Self.artistMatchesLibraryTarget(trackArtist: s.artist, targetArtist: cleanTarget) {
                matchedSongs.append(s)
                if !foundExactCasing && Self.normalizedArtistName(s.artist) == normTarget {
                    canonicalName = s.artist.trimmingCharacters(in: .whitespacesAndNewlines)
                    foundExactCasing = true
                }
            }
        }

        let stagedIds = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.stagedTemporaryTrackDbIds }
        let albums = Self.aggregateLibraryAlbums(from: matchedSongs, excludingStagedDbIds: stagedIds).map { alb -> AlbumInfo in
            var copy = alb
            copy.isLibraryView = true
            return copy
        }

        return ArtistLibraryDetailResponse(
            artist: canonicalName,
            trackCount: matchedSongs.count,
            albumCount: albums.count,
            albums: albums,
            songs: matchedSongs
        )
    }

    public func getLibraryAlbums(forceRefresh: Bool = false) -> [AlbumInfo] {
        let songs = getLibrarySongs(forceRefresh: forceRefresh)
        let stagedIds = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.stagedTemporaryTrackDbIds }
        return Self.aggregateLibraryAlbums(from: songs, excludingStagedDbIds: stagedIds)
    }

    public func getLibraryAlbumTracks(album: String, artist: String) -> [TrackInfo] {
        let cleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAlbum.isEmpty else { return [] }
        let songs = getLibrarySongs()
        var matched: [TrackInfo] = []
        for s in songs {
            if MusicKitManager.albumMatches(s.album, s.artist, cleanAlbum, artist) {
                var copy = s
                copy.index = matched.count + 1
                matched.append(copy)
            }
        }
        return matched
    }

    public func getLibraryRecent(
        limitAlbums: Int = 30,
        limitSongs: Int = 60,
        forceRefresh: Bool = false
    ) -> LibraryRecentResponse {
        let songs = getLibrarySongs(forceRefresh: forceRefresh)
        let stagedIds = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.stagedTemporaryTrackDbIds }

        let sortedSongs = songs.sorted { lhs, rhs in
            let lDate = lhs.dateAdded ?? 0
            let rDate = rhs.dateAdded ?? 0
            if lDate != rDate {
                return lDate > rDate
            }
            let lIdx = lhs.index ?? 0
            let rIdx = rhs.index ?? 0
            if lIdx != rIdx {
                return lIdx > rIdx
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        let recentSongs = Array(sortedSongs.prefix(max(0, limitSongs)))

        var mergedAlbums = Self.aggregateLibraryAlbums(from: songs, excludingStagedDbIds: stagedIds)
        let cachedCloudAlbums = MusicKitManager.shared.getCachedUserLibraryAlbumsSnapshot()
        if !cachedCloudAlbums.isEmpty {
            let stagedAlbums = PlaybackStateStore.shared.stagedAlbumCandidatesSnapshot()
            for c in cachedCloudAlbums {
                if let matchIdx = mergedAlbums.firstIndex(where: { item in
                    (!c.id.isEmpty && !item.id.isEmpty && c.id.caseInsensitiveCompare(item.id) == .orderedSame) ||
                    MusicKitManager.albumMatches(c.name, c.artist, item.name, item.artist)
                }) {
                    var updated = mergedAlbums[matchIdx]
                    if (Int(updated.id) ?? 0) < 10_000_000, (Int(c.id) ?? 0) >= 10_000_000 {
                        updated.id = c.id
                    }
                    if updated.catalogAlbumId == nil, let cid = c.catalogAlbumId {
                        updated.catalogAlbumId = cid
                    }
                    if (!updated.artwork.hasPrefix("http") && c.artwork.hasPrefix("http")) || (updated.artwork.isEmpty && !c.artwork.isEmpty) {
                        updated.artwork = c.artwork
                    }
                    if let cDate = c.dateAdded, cDate > (updated.dateAdded ?? 0) {
                        updated.dateAdded = cDate
                    }
                    if let cCount = c.trackCount, cCount > (updated.trackCount ?? 0) {
                        updated.trackCount = cCount
                    }
                    if let cLibCount = c.libraryTrackCount, cLibCount > (updated.libraryTrackCount ?? 0) {
                        updated.libraryTrackCount = cLibCount
                    }
                    if updated.catalogTrackCount == nil, let catCnt = c.catalogTrackCount {
                        updated.catalogTrackCount = catCnt
                    }
                    if updated.isCompleteInLibrary == nil, let comp = c.isCompleteInLibrary {
                        updated.isCompleteInLibrary = comp
                    }
                    mergedAlbums[matchIdx] = updated
                } else {
                    if !MusicKitManager.shared.isExplicitlyAddedAlbumInSession(albumId: c.id, name: c.name, artist: c.artist),
                       stagedAlbums.contains(where: { MusicKitManager.albumMatches(c.name, c.artist, $0.album, $0.artist) }) {
                        continue
                    }
                    var cloudCopy = c
                    cloudCopy.inLibrary = true
                    mergedAlbums.append(cloudCopy)
                }
            }
            mergedAlbums.sort { lhs, rhs in
                let lDate = lhs.dateAdded ?? 0
                let rDate = rhs.dateAdded ?? 0
                if lDate != rDate {
                    return lDate > rDate
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }

        let recentCloudAlbums = MusicKitManager.shared.getRecentlyAddedLibraryAlbumsSnapshot()
        for r in recentCloudAlbums.reversed() {
            if let existingIdx = mergedAlbums.firstIndex(where: { item in
                (!r.id.isEmpty && !item.id.isEmpty && r.id.caseInsensitiveCompare(item.id) == .orderedSame) ||
                MusicKitManager.albumMatches(r.name, r.artist, item.name, item.artist)
            }) {
                var promoted = mergedAlbums.remove(at: existingIdx)
                if (Int(promoted.id) ?? 0) < 10_000_000, (Int(r.id) ?? 0) >= 10_000_000 {
                    promoted.id = r.id
                }
                if promoted.catalogAlbumId == nil, let cid = r.catalogAlbumId {
                    promoted.catalogAlbumId = cid
                }
                if (promoted.artwork.isEmpty || (!promoted.artwork.hasPrefix("http") && r.artwork.hasPrefix("http"))) && !r.artwork.isEmpty {
                    promoted.artwork = r.artwork
                }
                if let rc = r.trackCount, rc > (promoted.trackCount ?? 0) {
                    promoted.trackCount = rc
                }
                if let rDate = r.dateAdded, rDate > (promoted.dateAdded ?? 0) {
                    promoted.dateAdded = rDate
                }
                if r.isCompleteInLibrary == true {
                    promoted.isCompleteInLibrary = true
                    if let catCount = r.catalogTrackCount {
                        promoted.catalogTrackCount = catCount
                        promoted.libraryTrackCount = max(promoted.libraryTrackCount ?? 0, catCount)
                    }
                }
                promoted.inLibrary = true
                mergedAlbums.insert(promoted, at: 0)
            } else {
                var fresh = r
                fresh.inLibrary = true
                mergedAlbums.insert(fresh, at: 0)
            }
        }

        let recentAlbums = Self.upgradeAlbumArtworksFromCache(Array(mergedAlbums.prefix(max(0, limitAlbums))))
        return LibraryRecentResponse(albums: recentAlbums, songs: recentSongs)
    }

    public static func aggregateLibraryAlbums(from songs: [TrackInfo], excludingStagedDbIds stagedIds: Set<Int>) -> [AlbumInfo] {
        struct Bucket {
            var id: String
            var name: String
            var primaryArtist: String
            var artistCounts: [String: Int]
            var artwork: String
            var trackCount: Int
            var maxOrderIndex: Int
            var maxDateAdded: Double
        }

        var bucketsByNormTitle: [String: [Bucket]] = [:]

        for (seqIdx, t) in songs.enumerated() {
            let album = t.album.trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = t.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let dbId = t.numericId ?? Int(t.id) ?? 0
            if dbId > 0 && stagedIds.contains(dbId) {
                continue
            }
            guard !album.isEmpty, t.duration > 0, !t.name.isEmpty else { continue }

            let normTitle = MusicKitManager.normalizedAlbumTitle(album)
            guard !normTitle.isEmpty else { continue }

            let orderIdx = t.index ?? (seqIdx + 1)
            let addedTs = t.dateAdded ?? 0

            var list = bucketsByNormTitle[normTitle] ?? []
            if let matchIdx = list.firstIndex(where: { b in
                MusicKitManager.albumMatches(b.name, b.primaryArtist, album, artist)
            }) {
                var b = list[matchIdx]
                b.trackCount += 1
                if orderIdx > b.maxOrderIndex {
                    b.maxOrderIndex = orderIdx
                }
                if addedTs > b.maxDateAdded {
                    b.maxDateAdded = addedTs
                }
                if !artist.isEmpty {
                    let count = (b.artistCounts[artist] ?? 0) + 1
                    b.artistCounts[artist] = count
                    let curBestCount = b.artistCounts[b.primaryArtist] ?? 0
                    if count > curBestCount || (count == curBestCount && artist.count < b.primaryArtist.count) {
                        b.primaryArtist = artist
                    }
                }
                if b.artwork.isEmpty && !t.artworkUrl.isEmpty {
                    b.artwork = t.artworkUrl
                } else if !b.artwork.hasPrefix("http") && t.artworkUrl.hasPrefix("http") {
                    b.artwork = t.artworkUrl
                }
                list[matchIdx] = b
            } else {
                let initialCounts = artist.isEmpty ? [:] : [artist: 1]
                list.append(Bucket(
                    id: "\(dbId)",
                    name: album,
                    primaryArtist: artist,
                    artistCounts: initialCounts,
                    artwork: t.artworkUrl,
                    trackCount: 1,
                    maxOrderIndex: orderIdx,
                    maxDateAdded: addedTs
                ))
            }
            bucketsByNormTitle[normTitle] = list
        }

        let allBuckets = bucketsByNormTitle.values.flatMap { $0 }
        let sortedBuckets = allBuckets.sorted { lhs, rhs in
            if lhs.maxDateAdded != rhs.maxDateAdded {
                return lhs.maxDateAdded > rhs.maxDateAdded
            }
            if lhs.maxOrderIndex != rhs.maxOrderIndex {
                return lhs.maxOrderIndex > rhs.maxOrderIndex
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return sortedBuckets.map { b in
            AlbumInfo(
                id: b.id,
                name: b.name,
                artist: b.primaryArtist,
                artwork: b.artwork,
                trackCount: b.trackCount,
                inLibrary: true,
                libraryTrackCount: b.trackCount,
                dateAdded: b.maxDateAdded > 0 ? b.maxDateAdded : nil
            )
        }
    }

    public func hasAlbumInLibrary(name: String, artist: String, minimumTracks: Int = 1) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return false }
        let songs = getLibrarySongs()
        let stagedIds = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.stagedTemporaryTrackDbIds }
        let targetMin = max(1, minimumTracks)
        var matched = 0
        for s in songs {
            let dbId = s.numericId ?? Int(s.id) ?? 0
            if dbId > 0 && stagedIds.contains(dbId) {
                continue
            }
            if MusicKitManager.albumMatches(s.album, s.artist, cleanName, artist) {
                matched += 1
                if matched >= targetMin {
                    return true
                }
            }
        }
        return false
    }
}
