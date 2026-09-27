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

        # Verify Music.app playback
        out = subprocess.check_output([
            "osascript", "-e",
            'tell application "Music" to get {player state as string, name of current track as string}'
        ]).decode().strip()
        self.assertIn("playing", out)

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
        self.assertTrue(tracks[0].get("is_current"), "Track 1 should be current")
        self.assertEqual(tracks[0].get("name"), "Лето 96")

    async def test_05_station_playback(self):
        """Verifies streaming an Apple Music curated radio station."""
        resp = await self._send_and_wait(
            "play_station",
            {"name": "Chill & Lo-Fi", "url": "https://music.apple.com/us/station/chill-station/ra.985484943"},
            expected_id="req-station"
        )
        self.assertEqual(resp.get("status"), "ok")
        await asyncio.sleep(2.0)

        out = subprocess.check_output([
            "osascript", "-e",
            'tell application "Music" to get player state as string'
        ]).decode().strip()
        self.assertEqual(out, "playing", "Music.app should be playing the station stream")

if __name__ == "__main__":
    unittest.main()
