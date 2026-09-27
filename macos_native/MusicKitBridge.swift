import Foundation
import MusicKit

@objc public class MusicKitBridge: NSObject {
    @objc public static let shared = MusicKitBridge()
    
    @objc public func requestAuthorization(completion: @escaping (Bool) -> Void) {
        Task {
            let status = await MusicAuthorization.request()
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }
    
    @objc public func search(query: String, completion: @escaping (String?) -> Void) {
        Task {
            do {
                let request = MusicCatalogSearchRequest(term: query, types: [Song.self])
                let response = try await request.response()
                
                var results: [[String: Any]] = []
                
                for song in response.songs {
                    results.append([
                        "id": song.id.rawValue,
                        "name": song.title,
                        "artist": song.artistName,
                        "album": song.albumTitle ?? "",
                        "artwork_url": song.artwork?.url(width: 300, height: 300)?.absoluteString ?? "",
                        "type": "song",
                        "url": song.url?.absoluteString ?? ""
                    ])
                }
                
                let jsonData = try JSONSerialization.data(withJSONObject: results, options: [])
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    DispatchQueue.main.async {
                        completion(jsonString)
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
            } catch {
                print("MusicKit search error: \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    @objc public func playTrack(storeID: String, completion: @escaping (Bool) -> Void) {
        Task {
            do {
                let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(storeID))
                let response = try await request.response()
                if let song = response.items.first {
                    ApplicationMusicPlayer.shared.queue = [song]
                    try await ApplicationMusicPlayer.shared.play()
                    DispatchQueue.main.async { completion(true) }
                } else {
                    DispatchQueue.main.async { completion(false) }
                }
            } catch {
                print("MusicKit play error: \(error)")
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
    
    @objc public func playQueue(storeIDs: [String], startIndex: Int, completion: @escaping (Bool) -> Void) {
        Task {
            do {
                let itemIDs = storeIDs.compactMap { MusicItemID($0) }
                let request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: itemIDs)
                let response = try await request.response()
                let items = response.items
                if !items.isEmpty {
                    let songMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id.rawValue, $0) })
                    let orderedSongs = storeIDs.compactMap { songMap[$0] }
                    let startSong = (startIndex >= 0 && startIndex < orderedSongs.count) ? orderedSongs[startIndex] : orderedSongs.first
                    
                    if let startSong = startSong {
                        ApplicationMusicPlayer.shared.queue = ApplicationMusicPlayer.Queue(for: orderedSongs, startingAt: startSong)
                        try await ApplicationMusicPlayer.shared.play()
                        DispatchQueue.main.async { completion(true) }
                        return
                    }
                }
                DispatchQueue.main.async { completion(false) }
            } catch {
                print("MusicKit playQueue error: \(error)")
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
    
    @objc public func pause() {
        ApplicationMusicPlayer.shared.pause()
    }
    
    @objc public func play() {
        Task {
            try? await ApplicationMusicPlayer.shared.play()
        }
    }
    
    @objc public func getPlaybackStatus() -> String {
        let state = ApplicationMusicPlayer.shared.state.playbackStatus
        switch state {
        case .playing: return "playing"
        case .paused: return "paused"
        default: return "stopped"
        }
    }
    
    @objc public func getCurrentTrackInfo() -> [String: Any]? {
        guard let currentEntry = ApplicationMusicPlayer.shared.queue.currentEntry,
              let item = currentEntry.item else {
            return nil
        }
        switch item {
        case .song(let song):
            let isPlaying = ApplicationMusicPlayer.shared.state.playbackStatus == .playing
            let pos = ApplicationMusicPlayer.shared.playbackTime
            return [
                "id": song.id.rawValue,
                "name": song.title,
                "artist": song.artistName,
                "album": song.albumTitle ?? "",
                "duration": song.duration ?? 0.0,
                "position": pos,
                "artwork_url": song.artwork?.url(width: 600, height: 600)?.absoluteString ?? "",
                "is_playing": isPlaying
            ]
        default:
            return nil
        }
    }
}
