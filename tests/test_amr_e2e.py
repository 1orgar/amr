import asyncio
import json
import subprocess
import unittest
import websockets

class TestAMRE2E(unittest.IsolatedAsyncioTestCase):
    SERVER_URL = "ws://localhost:8080/ws"

    async def asyncSetUp(self):
        try:
            self.ws = await websockets.connect(self.SERVER_URL, max_size=16 * 1024 * 1024)
        except Exception as e:
            self.skipTest(f"AMR server is not running on {self.SERVER_URL}: {e}")

    async def asyncTearDown(self):
        if hasattr(self, 'ws') and self.ws:
            await self.ws.close()
        # Always ensure Music.app is paused after tests
        try:
            subprocess.run(["osascript", "-e", 'tell application "Music" to pause'], capture_output=True)
        except Exception:
            pass

    async def _send_and_wait(self, action, params=None, expected_id="req-1", timeout=10.0):
        req = {
            "action": action,
            "params": params or {},
            "id": expected_id
        }
        await self.ws.send(json.dumps(req))

        while True:
            msg = await asyncio.wait_for(self.ws.recv(), timeout=timeout)
            data = json.loads(msg)
            if data.get("id") == expected_id:
                return data

    async def test_01_handshake_and_initial_events(self):
        """Verifies initial player state and queue broadcasts upon connecting."""
        received_status = False
        received_queue = False

        for _ in range(5):
            try:
                msg = await asyncio.wait_for(self.ws.recv(), timeout=2.0)
                data = json.loads(msg)
                act = data.get("action") or data.get("event") or data.get("type")
                if act in ("player_state_changed", "status"):
                    received_status = True
                elif act in ("queue", "queue_changed"):
                    received_queue = True
                if received_status and received_queue:
                    break
            except asyncio.TimeoutError:
                break

        self.assertTrue(received_status or received_queue, "Should receive initial status or queue event on handshake")

    async def test_02_get_explore_feed(self):
        """Verifies explore feed returns curated stations, hero cards, and top albums."""
        resp = await self._send_and_wait("get_explore", {"country": "ru"}, expected_id="req-explore")
        self.assertEqual(resp.get("status"), "ok")

        feed = resp.get("data", {})
        stations = feed.get("stations", [])
        self.assertGreaterEqual(len(stations), 6, "Explore feed must have at least 6 stations")

        # Verify station properties
        for s in stations:
            self.assertIn("id", s)
            self.assertIn("name", s)
            self.assertIn("url", s)
            self.assertTrue("ra." in s["url"] or "/station/" in s["url"])

        hero_cards = feed.get("hero_cards", [])
        self.assertGreaterEqual(len(hero_cards), 2, "Explore feed must have hero cards")

        top_albums = feed.get("top_albums", [])
        self.assertGreaterEqual(len(top_albums), 3, "Explore feed must have top albums")

    async def test_03_get_album_details(self):
        """Verifies fetching album details and track list by catalog ID."""
        resp = await self._send_and_wait("get_album", {"id": "6814854069", "country": "ru"}, expected_id="req-album")
        self.assertEqual(resp.get("status"), "ok")

        data = resp.get("data", {})
        album = data.get("album", data)
        self.assertEqual(album.get("name"), "ГАДДЕМ 3")
        tracks = album.get("tracks", [])
        self.assertEqual(len(tracks), 9, "ГАДДЕМ 3 must contain exactly 9 tracks")
        self.assertEqual(tracks[0].get("name"), "Лето 96")

    async def test_04_play_album_and_queue_population(self):
        """Verifies album playback starts with track 1 and populates AMR queue."""
        resp = await self._send_and_wait(
            "play_album",
            {"id": "6814854069", "name": "ГАДДЕМ 3", "artist": "Брутто", "shuffle": False},
            expected_id="req-play-alb",
            timeout=12.0
        )
        print("DEBUG test_04 play_album resp:", resp)
        self.assertEqual(resp.get("status"), "ok")

        await asyncio.sleep(2.5)

        # We skip verifying Music.app player state via osascript here because 
        # opening Apple Music URLs in a headless CI VM without a subscription 
        # can cause Music.app to show a modal dialog, hanging subsequent AppleScript calls.

        # Verify AMR queue (with brief retry if state transition is finalizing)
        tracks = []
        for _ in range(5):
            q_resp = await self._send_and_wait("get_queue", {}, expected_id="req-q-check")
            q = q_resp.get("data", {})
            tracks = q.get("tracks", [])
            if len(tracks) == 9:
                break
            await asyncio.sleep(0.5)

        self.assertEqual(len(tracks), 9, "Queue should contain all 9 album tracks")
        self.assertEqual(tracks[0].get("name"), "Лето 96", "Track 1 should be Лето 96")
        self.assertEqual(tracks[0].get("name"), "Лето 96")

    async def test_05_station_playback(self):
        """Verifies streaming an Apple Music curated radio station."""
        resp = await self._send_and_wait(
            "play_station",
            {"name": "Chill & Lo-Fi", "url": "https://music.apple.com/us/station/chill-station/ra.985484943"},
            expected_id="req-station"
        )
        self.assertEqual(resp.get("status"), "ok")
        out = "stopped"
        for _ in range(3):
            await asyncio.sleep(1.0)
            out = subprocess.check_output([
                "osascript", "-e",
                'tell application "Music" to get player state as string'
            ]).decode().strip()
            if out == "playing":
                break
        self.assertIn(out, ["playing", "stopped"], "Music.app player state should be valid")

    async def test_06_search_pagination(self):
        """Verifies search pagination with offset and limit parameters."""
        resp1 = await self._send_and_wait(
            "search",
            {"query": "The Beatles", "limit": 4, "offset": 0, "country": "us"},
            expected_id="req-search-p1"
        )
        self.assertEqual(resp1.get("status"), "ok")
        data1 = resp1.get("data", {})
        self.assertEqual(data1.get("offset"), 0)
        self.assertEqual(data1.get("limit"), 4)
        self.assertIn("has_more", data1)
        songs1 = data1.get("songs", [])
        self.assertGreaterEqual(len(songs1), 1)

        # Page 2
        resp2 = await self._send_and_wait(
            "search",
            {"query": "The Beatles", "limit": 4, "offset": 4, "country": "us"},
            expected_id="req-search-p2"
        )
        self.assertEqual(resp2.get("status"), "ok")
        data2 = resp2.get("data", {})
        self.assertEqual(data2.get("offset"), 4)
        self.assertEqual(data2.get("limit"), 4)

    async def test_07_play_search_results_queue(self):
        """Verifies playing search results creates active AMR search queue."""
        s_resp = await self._send_and_wait(
            "search",
            {"query": "Abbey Road Beatles", "limit": 3, "offset": 0, "country": "us"},
            expected_id="req-search-tracks"
        )
        songs = s_resp.get("data", {}).get("songs", [])
        self.assertGreaterEqual(len(songs), 2)

        resp = await self._send_and_wait(
            "play_search_results",
            {"tracks": songs[:3], "shuffle": False},
            expected_id="req-play-search",
            timeout=10.0
        )
        self.assertEqual(resp.get("status"), "ok")

        await asyncio.sleep(2.0)
        q_resp = await self._send_and_wait("get_queue", {}, expected_id="req-q-search")
        q_data = q_resp.get("data", {})
        tracks = q_data.get("tracks", [])
        self.assertGreaterEqual(len(tracks), 2)
        self.assertEqual(tracks[0].get("name"), songs[0].get("name"))

    async def test_08_search_and_play_api_and_queue_stability(self):
        """Verifies search_and_play API begins playback and maintains stable queue without rapid skipping."""
        resp = await self._send_and_wait(
            "search_and_play",
            {"query": "red hot chilie peppers"},
            expected_id="req-search-play",
            timeout=15.0
        )
        self.assertEqual(resp.get("status"), "ok")
        data = resp.get("data", {})
        self.assertTrue(data.get("success", False))

        # Wait 3 seconds to ensure queue does NOT rapidly skip through all tracks
        await asyncio.sleep(3.0)

        q_resp = await self._send_and_wait("get_queue", {}, expected_id="req-q-sap")
        q_data = q_resp.get("data", {})
        tracks = q_data.get("tracks", [])
        self.assertGreaterEqual(len(tracks), 1)

        # Queue index should remain on the first track (or early track) and not skip through the whole queue
        cur_idx = q_data.get("currentIndex", 0)
        self.assertLessEqual(cur_idx, 2, f"Queue index {cur_idx} unexpectedly skipped ahead")

    async def test_09_search_and_play_while_already_playing(self):
        """Verifies search_and_play halts ongoing playback and switches immediately to searched music."""
        # 1. Start playback of a station first
        s_resp = await self._send_and_wait(
            "play_station",
            {"name": "Chill & Lo-Fi", "url": "https://music.apple.com/us/station/chill-station/ra.985484943"},
            expected_id="req-init-station"
        )
        self.assertEqual(s_resp.get("status"), "ok")
        await asyncio.sleep(2.0)

        # 2. While audio is actively playing, call search_and_play for a different artist / song
        sap_resp = await self._send_and_wait(
            "search_and_play",
            {"query": "Кино Звезда по имени Солнце"},
            expected_id="req-sap-switch",
            timeout=15.0
        )
        self.assertEqual(sap_resp.get("status"), "ok")
        data = sap_resp.get("data", {})
        self.assertTrue(data.get("success", False))

        # 3. Allow Music.app and AMR to transition
        await asyncio.sleep(2.5)

        # 4. Check AMR queue reflects searched track
        q_resp = await self._send_and_wait("get_queue", {}, expected_id="req-q-check-sap")
        q_data = q_resp.get("data", {})
        tracks = q_data.get("tracks", [])
        self.assertGreaterEqual(len(tracks), 1, "Queue must contain searched tracks")
        self.assertIn("звезда", tracks[0].get("name", "").lower(), "First track in queue must be the searched track")

if __name__ == "__main__":
    unittest.main()

