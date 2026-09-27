import subprocess
import json
import os
import time
import urllib.request
import urllib.parse
import hashlib
from typing import Dict, Any, List, Optional, Tuple

ARTWORK_CACHE_DIR = os.path.expanduser("~/.cache/amr_artwork")
os.makedirs(ARTWORK_CACHE_DIR, exist_ok=True)

def run_applescript(script: str, timeout: float = 6.0) -> Tuple[bool, str]:
    try:
        res = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            timeout=timeout
        )
        if res.returncode == 0:
            return True, res.stdout.strip()
        else:
            return False, res.stderr.strip()
    except subprocess.TimeoutExpired:
        return False, "AppleScript timed out"
    except Exception as e:
        return False, str(e)

def upgrade_artwork_url(url: str, size: int = 600) -> str:
    if not url:
        return ""
    # Standardize Apple mzstatic URLs to high-res square
    # E.g. /100x100bb.jpg -> /600x600bb.jpg, /170x170bb.png -> /600x600bb.png
    import re
    cleaned = re.sub(r'/\d+x\d+bb\.(jpg|png|webp)', f'/{size}x{size}bb.\\1', url)
    return cleaned

class AppleMusicBridge:
    def __init__(self):
        self._last_status: Dict[str, Any] = {}
        self._last_status_time: float = 0
        self._cached_artwork_path: Optional[str] = None
        self._cached_track_id: Optional[str] = None
        self._artwork_version: int = int(time.time())

    def get_status(self) -> Dict[str, Any]:
        script = """
        tell application "Music"
            try
                set pState to player state as string
                set v to sound volume
                set shuf to shuffle enabled
                set rep to song repeat as string
                
                if pState is not "stopped" then
                    set tName to name of current track
                    set tArtist to artist of current track
                    set tAlbum to album of current track
                    set tDur to duration of current track
                    set tPos to player position
                    set tId to id of current track
                    set hasArt to (count of artworks of current track) > 0
                    return (pState & "|||" & v & "|||" & shuf & "|||" & rep & "|||" & tName & "|||" & tArtist & "|||" & tAlbum & "|||" & tDur & "|||" & tPos & "|||" & tId & "|||" & hasArt)
                else
                    return (pState & "|||" & v & "|||" & shuf & "|||" & rep)
                end if
            on error errMsg
                return "error|||" & errMsg
            end try
        end tell
        """
        ok, res = run_applescript(script)
        if not ok or not res:
            return {
                "player_state": "stopped",
                "volume": 50,
                "shuffle": False,
                "repeat": "off",
                "track": None,
                "error": res or "Music app unreachable"
            }

        parts = res.split("|||")
        if parts[0] == "error":
            return {
                "player_state": "stopped",
                "volume": 50,
                "shuffle": False,
                "repeat": "off",
                "track": None,
                "error": parts[1] if len(parts) > 1 else "Unknown error"
            }

        state = parts[0].lower()
        volume = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 50
        shuffle = (parts[2].lower() == "true") if len(parts) > 2 else False
        repeat_mode = parts[3].lower() if len(parts) > 3 else "off"

        status: Dict[str, Any] = {
            "player_state": state,
            "volume": volume,
            "shuffle": shuffle,
            "repeat": repeat_mode,
            "track": None,
            "server_time": time.time()
        }

        if state != "stopped" and len(parts) >= 11:
            name = parts[4]
            artist = parts[5]
            album = parts[6]
            try:
                duration = float(parts[7].replace(",", "."))
            except Exception:
                duration = 0.0
            try:
                position = float(parts[8].replace(",", "."))
            except Exception:
                position = 0.0
            track_id = parts[9]
            has_art = (parts[10].lower() == "true")

            if track_id != self._cached_track_id:
                self._cached_track_id = track_id
                self._artwork_version = int(time.time() * 1000)

            status["track"] = {
                "id": track_id,
                "name": name,
                "artist": artist,
                "album": album,
                "duration": duration,
                "position": position,
                "has_artwork": has_art,
                "artwork_url": f"/api/artwork?track_id={track_id}&v={self._artwork_version}" if has_art else None
            }

        self._last_status = status
        self._last_status_time = time.time()
        return status

    def play(self) -> bool:
        ok, _ = run_applescript('tell application "Music" to play')
        return ok

    def pause(self) -> bool:
        ok, _ = run_applescript('tell application "Music" to pause')
        return ok

    def playpause(self) -> bool:
        ok, _ = run_applescript('tell application "Music" to playpause')
        return ok

    def next_track(self) -> bool:
        ok, _ = run_applescript('tell application "Music" to next track')
        return ok

    def previous_track(self) -> bool:
        ok, _ = run_applescript('tell application "Music" to previous track')
        return ok

    def seek(self, position: float) -> bool:
        ok, _ = run_applescript(f'tell application "Music" to set player position to {position}')
        return ok

    def set_volume(self, volume: int) -> bool:
        vol = max(0, min(100, int(volume)))
        ok, _ = run_applescript(f'tell application "Music" to set sound volume to {vol}')
        return ok

    def set_shuffle(self, enabled: bool) -> bool:
        val = "true" if enabled else "false"
        ok, _ = run_applescript(f'tell application "Music" to set shuffle enabled to {val}')
        return ok

    def set_repeat(self, mode: str) -> bool:
        mode_val = "off"
        if mode in ("one", "all", "off"):
            mode_val = mode
        ok, _ = run_applescript(f'tell application "Music" to set song repeat to {mode_val}')
        return ok

    def play_track(self, track_id: str) -> bool:
        script = f"""
        tell application "Music"
            try
                set t to (first track whose id is {track_id})
                play t
                return "ok"
            on error errMsg
                return "error: " & errMsg
            end try
        end tell
        """
        ok, res = run_applescript(script)
        return ok and res == "ok"

    def play_playlist(self, playlist_name: str, track_index: Optional[int] = None, track_id: Optional[str] = None) -> bool:
        escaped_name = playlist_name.replace('"', '\\"')
        
        # If track_id is provided, play exact track by ID inside the playlist to keep playlist context
        if track_id:
            script = f"""
            tell application "Music"
                try
                    set p to playlist "{escaped_name}"
                    set t to (first track of p whose id is {track_id})
                    play t
                    return "ok"
                on error
                    try
                        play (first track whose id is {track_id})
                        return "ok"
                    on error errMsg
                        return "error: " & errMsg
                    end try
                end try
            end tell
            """
        elif track_index is not None and track_index > 0:
            script = f"""
            tell application "Music"
                try
                    set p to playlist "{escaped_name}"
                    play track {track_index} of p
                    return "ok"
                on error errMsg
                    return "error: " & errMsg
                end try
            end tell
            """
        else:
            script = f"""
            tell application "Music"
                try
                    set p to playlist "{escaped_name}"
                    play p
                    return "ok"
                on error errMsg
                    return "error: " & errMsg
                end try
            end tell
            """
        ok, res = run_applescript(script)
        return ok and res == "ok"

    def play_cloud_url(self, url: str, track_name: Optional[str] = None, artist_name: Optional[str] = None) -> bool:
        # 1. If track_name is provided, check if it already exists in local library for instant playback
        if track_name:
            escaped_title = track_name.replace('"', '\\"')
            script_local = f"""
            tell application "Music"
                try
                    set res to search (get library playlist 1) for "{escaped_title}"
                    if (count of res) > 0 then
                        play (first item of res)
                        return "ok_local"
                    end if
                end try
                return "not_found"
            end tell
            """
            ok, res = run_applescript(script_local)
            if ok and res == "ok_local":
                return True

        # 2. Fallback to Apple Music catalog URL opening
        escaped_url = url.replace('"', '\\"')
        script_cloud = f"""
        tell application "Music"
            try
                open location "{escaped_url}"
                delay 0.6
                play
                return "ok"
            on error errMsg
                return "error: " & errMsg
            end try
        end tell
        """
        ok, res = run_applescript(script_cloud)
        if ok and res == "ok":
            return True

        # Also trigger system open as backup
        try:
            subprocess.run(["open", "-a", "Music", url], timeout=3.0)
            time.sleep(0.5)
            run_applescript('tell application "Music" to play')
            return True
        except Exception:
            return False

    def get_artwork(self, track_id: Optional[str] = None) -> Optional[bytes]:
        cache_key = track_id if track_id else "current"
        cache_path = os.path.join(ARTWORK_CACHE_DIR, f"{cache_key}.jpg")

        if track_id:
            target_expr = f"(first track whose id is {track_id})"
        else:
            target_expr = "current track"

        script = f"""
        set filePath to "{cache_path}"
        tell application "Music"
            try
                if player state is not stopped or "{track_id}" is not "" then
                    set t to {target_expr}
                    if (count of artworks of t) > 0 then
                        set rawData to raw data of artwork 1 of t
                        set fileRef to open for access (POSIX file filePath) with write permission
                        set eof of fileRef to 0
                        write rawData to fileRef
                        close access fileRef
                        return "ok"
                    end if
                end if
                return "none"
            on error errMsg
                try
                    close access (POSIX file filePath)
                end try
                return "error: " & errMsg
            end try
        end tell
        """
        ok, res = run_applescript(script)
        if ok and res == "ok" and os.path.exists(cache_path):
            try:
                with open(cache_path, "rb") as f:
                    return f.read()
            except Exception as e:
                print(f"[Artwork] Read error: {e}")
        return None

    def get_playlists(self) -> List[Dict[str, Any]]:
        # Use custom delimiter ___PL_SEP___ to avoid comma split issues
        script = """
        tell application "Music"
            set pList to every playlist
            set out to ""
            repeat with p in pList
                try
                    set pName to name of p
                    set pId to id of p
                    set pKind to special kind of p as string
                    set pCount to count of tracks of p
                    set entry to (pName & "|||" & pId & "|||" & pKind & "|||" & pCount)
                    if out is "" then
                        set out to entry
                    else
                        set out to out & "___PL_SEP___" & entry
                    end if
                end try
            end repeat
            return out
        end tell
        """
        ok, res = run_applescript(script, timeout=8.0)
        if not ok or not res:
            return []

        items = res.split("___PL_SEP___")
        playlists = []
        for item in items:
            parts = item.split("|||")
            if len(parts) >= 4:
                name = parts[0]
                playlists.append({
                    "name": name,
                    "id": parts[1],
                    "special_kind": parts[2],
                    "track_count": int(parts[3]) if parts[3].isdigit() else 0
                })
        return playlists

    def get_playlist_tracks(self, playlist_name: str) -> List[Dict[str, Any]]:
        escaped_name = playlist_name.replace('"', '\\"')
        # Use custom delimiter ___TRACK_SEP___ to avoid splitting on commas in song titles or artist names
        script = f"""
        tell application "Music"
            try
                set p to playlist "{escaped_name}"
                set tList to tracks of p
                set out to ""
                repeat with t in tList
                    set tName to name of t
                    set tArtist to artist of t
                    set tAlbum to album of t
                    set tDur to duration of t
                    set tId to id of t
                    set entry to (tName & "|||" & tArtist & "|||" & tAlbum & "|||" & tDur & "|||" & tId)
                    if out is "" then
                        set out to entry
                    else
                        set out to out & "___TRACK_SEP___" & entry
                    end if
                end repeat
                return out
            on error
                return ""
            end try
        end tell
        """
        ok, res = run_applescript(script, timeout=12.0)
        if not ok or not res:
            return []

        items = res.split("___TRACK_SEP___")
        tracks = []
        for idx, item in enumerate(items):
            parts = item.split("|||")
            if len(parts) >= 5:
                try:
                    duration = float(parts[3].replace(",", "."))
                except Exception:
                    duration = 0.0
                tracks.append({
                    "index": idx + 1,
                    "name": parts[0],
                    "artist": parts[1],
                    "album": parts[2],
                    "duration": duration,
                    "id": parts[4]
                })
        return tracks

    def search_library(self, query: str) -> List[Dict[str, Any]]:
        if not query.strip():
            return []
        escaped_query = query.replace('"', '\\"')
        script = f"""
        tell application "Music"
            try
                set res to search (get library playlist 1) for "{escaped_query}"
                set out to ""
                repeat with t in res
                    set tName to name of t
                    set tArtist to artist of t
                    set tAlbum to album of t
                    set tDur to duration of t
                    set tId to id of t
                    set entry to (tName & "|||" & tArtist & "|||" & tAlbum & "|||" & tDur & "|||" & tId)
                    if out is "" then
                        set out to entry
                    else
                        set out to out & "___SEARCH_SEP___" & entry
                    end if
                end repeat
                return out
            on error
                return ""
            end try
        end tell
        """
        ok, res = run_applescript(script, timeout=8.0)
        if not ok or not res:
            return []

        items = res.split("___SEARCH_SEP___")
        results = []
        for item in items:
            parts = item.split("|||")
            if len(parts) >= 5:
                try:
                    duration = float(parts[3].replace(",", "."))
                except Exception:
                    duration = 0.0
                results.append({
                    "type": "library_track",
                    "id": parts[4],
                    "name": parts[0],
                    "artist": parts[1],
                    "album": parts[2],
                    "duration": duration
                })
        return results

    def search_cloud(self, query: str, country: str = "ru") -> Dict[str, Any]:
        """
        Categorized cloud search across Apple Music:
        - artists (Исполнители)
        - songs (Треки)
        - albums (Альбомы)
        """
        if not query.strip():
            return {"artists": [], "songs": [], "albums": [], "all": []}
        
        encoded = urllib.parse.quote(query.strip())
        
        data_out: Dict[str, Any] = {
            "artists": [],
            "songs": [],
            "albums": [],
            "all": []
        }

        # 1. Search Artists
        try:
            url_artist = f"https://itunes.apple.com/search?term={encoded}&entity=musicArtist&country={country}&limit=6"
            req = urllib.request.Request(url_artist, headers={"User-Agent": "Mozilla/5.0 AppleMusicRemote/1.0"})
            with urllib.request.urlopen(req, timeout=4.0) as resp:
                d = json.loads(resp.read().decode())
                for a in d.get("results", []):
                    data_out["artists"].append({
                        "type": "artist",
                        "id": str(a.get("artistId", "")),
                        "name": a.get("artistName", ""),
                        "genre": a.get("primaryGenreName", ""),
                        "url": a.get("artistLinkUrl", "")
                    })
        except Exception as e:
            print(f"[Search Artists] Error: {e}")

        # 2. Search Songs
        try:
            url_song = f"https://itunes.apple.com/search?term={encoded}&entity=song&country={country}&limit=25"
            req = urllib.request.Request(url_song, headers={"User-Agent": "Mozilla/5.0 AppleMusicRemote/1.0"})
            with urllib.request.urlopen(req, timeout=5.0) as resp:
                d = json.loads(resp.read().decode())
                for s in d.get("results", []):
                    duration_ms = s.get("trackTimeMillis", 0)
                    art = upgrade_artwork_url(s.get("artworkUrl100", ""), size=600)
                    song_item = {
                        "type": "cloud_song",
                        "id": str(s.get("trackId", "")),
                        "name": s.get("trackName", ""),
                        "artist": s.get("artistName", ""),
                        "album": s.get("collectionName", ""),
                        "artwork": art,
                        "duration": round(duration_ms / 1000.0, 1),
                        "url": s.get("trackViewUrl", ""),
                        "preview_url": s.get("previewUrl", ""),
                        "release_date": s.get("releaseDate", "")[:10] if s.get("releaseDate") else ""
                    }
                    data_out["songs"].append(song_item)
                    data_out["all"].append(song_item)
        except Exception as e:
            print(f"[Search Songs] Error: {e}")

        # 3. Search Albums
        try:
            url_album = f"https://itunes.apple.com/search?term={encoded}&entity=album&country={country}&limit=12"
            req = urllib.request.Request(url_album, headers={"User-Agent": "Mozilla/5.0 AppleMusicRemote/1.0"})
            with urllib.request.urlopen(req, timeout=5.0) as resp:
                d = json.loads(resp.read().decode())
                for al in d.get("results", []):
                    art = upgrade_artwork_url(al.get("artworkUrl100", ""), size=600)
                    album_item = {
                        "type": "cloud_album",
                        "id": str(al.get("collectionId", "")),
                        "name": al.get("collectionName", ""),
                        "artist": al.get("artistName", ""),
                        "artwork": art,
                        "track_count": al.get("trackCount", 0),
                        "url": al.get("collectionViewUrl", ""),
                        "release_date": al.get("releaseDate", "")[:10] if al.get("releaseDate") else ""
                    }
                    data_out["albums"].append(album_item)
        except Exception as e:
            print(f"[Search Albums] Error: {e}")

        return data_out

    def get_explore_feed(self, country: str = "ru") -> Dict[str, Any]:
        """
        Fetches 'Главное / Обзор' Apple Music cloud feed:
        - Top Songs (Топ-чарт 50 треков)
        - Top Albums (Топ-чарт 50 альбомов с унифицированным разрешением 600x600)
        - Hot Picks (Горячие новинки)
        - Curated Genres (Жанры)
        """
        explore: Dict[str, Any] = {
            "country": country,
            "top_songs": [],
            "top_albums": [],
            "hot_tracks": [],
            "genres": [
                {"name": "Поп", "query": "Pop hits", "color": "linear-gradient(135deg, #ff416c, #ff4b2b)"},
                {"name": "Рок и Альтернатива", "query": "Rock", "color": "linear-gradient(135deg, #4b6cb7, #182848)"},
                {"name": "Хип-Хоп / Рэп", "query": "Hip-Hop", "color": "linear-gradient(135deg, #f7971e, #ffd200)"},
                {"name": "Электроника и Dance", "query": "Electronic dance", "color": "linear-gradient(135deg, #8a2387, #e94057, #f27121)"},
                {"name": "Chill / Релакс", "query": "Chillout lounge", "color": "linear-gradient(135deg, #00b4db, #0083b0)"},
                {"name": "Классика", "query": "Classical masterpieces", "color": "linear-gradient(135deg, #654ea3, #eaafc8)"},
                {"name": "Саундтреки & OST", "query": "Soundtracks", "color": "linear-gradient(135deg, #11998e, #38ef7d)"}
            ]
        }

        # 1. Top Songs Chart
        try:
            url_top_songs = f"https://rss.applemarketingtools.com/api/v2/{country}/music/most-played/50/songs.json"
            req = urllib.request.Request(url_top_songs, headers={"User-Agent": "Mozilla/5.0 AppleMusicRemote/1.0"})
            with urllib.request.urlopen(req, timeout=5.0) as resp:
                data = json.loads(resp.read().decode())
                for rank, item in enumerate(data.get("feed", {}).get("results", []), 1):
                    art = upgrade_artwork_url(item.get("artworkUrl100", ""), size=600)
                    explore["top_songs"].append({
                        "rank": rank,
                        "id": item.get("id", ""),
                        "name": item.get("name", ""),
                        "artist": item.get("artistName", ""),
                        "artwork": art,
                        "url": item.get("url", ""),
                        "type": "cloud_song"
                    })
        except Exception as e:
            print(f"[Explore] Top songs error: {e}")

        # 2. Top Albums (Standardized 600x600)
        try:
            url_top_albums = f"https://rss.applemarketingtools.com/api/v2/{country}/music/most-played/50/albums.json"
            req = urllib.request.Request(url_top_albums, headers={"User-Agent": "Mozilla/5.0 AppleMusicRemote/1.0"})
            with urllib.request.urlopen(req, timeout=5.0) as resp:
                data = json.loads(resp.read().decode())
                for rank, item in enumerate(data.get("feed", {}).get("results", []), 1):
                    art = upgrade_artwork_url(item.get("artworkUrl100", ""), size=600)
                    explore["top_albums"].append({
                        "rank": rank,
                        "id": item.get("id", ""),
                        "name": item.get("name", ""),
                        "artist": item.get("artistName", ""),
                        "artwork": art,
                        "url": item.get("url", ""),
                        "type": "cloud_album"
                    })
        except Exception as e:
            print(f"[Explore] Top albums error: {e}")

        # 3. Hot Singles (iTunes RSS)
        try:
            url_hot = f"https://itunes.apple.com/{country}/rss/topsongs/limit=25/json"
            req = urllib.request.Request(url_hot, headers={"User-Agent": "Mozilla/5.0 AppleMusicRemote/1.0"})
            with urllib.request.urlopen(req, timeout=5.0) as resp:
                data = json.loads(resp.read().decode())
                entries = data.get("feed", {}).get("entry", [])
                for entry in entries:
                    name = entry.get("im:name", {}).get("label", "")
                    artist = entry.get("im:artist", {}).get("label", "")
                    images = entry.get("im:image", [])
                    art_raw = images[-1].get("label", "") if images else ""
                    art = upgrade_artwork_url(art_raw, size=600)
                    link = entry.get("link", [{}])[0].get("attributes", {}).get("href", "")
                    if name and link:
                        explore["hot_tracks"].append({
                            "name": name,
                            "artist": artist,
                            "artwork": art,
                            "url": link,
                            "type": "cloud_song"
                        })
        except Exception as e:
            print(f"[Explore] Hot tracks error: {e}")

        return explore
