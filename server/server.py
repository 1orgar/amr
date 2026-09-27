import os
import sys
import json
import time
import socket
import threading
import queue
import urllib.parse
from http.server import HTTPServer, ThreadingHTTPServer, BaseHTTPRequestHandler
from typing import Dict, Any, List, Set

# Add parent directory to path
base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if base_dir not in sys.path:
    sys.path.insert(0, base_dir)

try:
    from server.config import load_config, save_config
    from server.apple_music_bridge import AppleMusicBridge
    from server.qr import generate_qr_svg
except ImportError:
    from config import load_config, save_config
    from apple_music_bridge import AppleMusicBridge
    from qr import generate_qr_svg

bridge = AppleMusicBridge()
sse_subscribers: Set[queue.Queue] = set()
sse_lock = threading.Lock()
last_known_status: Dict[str, Any] = {}

def get_lan_ips() -> List[str]:
    ips = []
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        primary_ip = s.getsockname()[0]
        s.close()
        ips.append(primary_ip)
    except Exception:
        pass

    try:
        hostname = socket.gethostname()
        for ip in socket.gethostbyname_ex(hostname)[2]:
            if not ip.startswith("127.") and ip not in ips:
                ips.append(ip)
    except Exception:
        pass

    if not ips:
        ips.append("127.0.0.1")
    return ips

def broadcast_status(status: Dict[str, Any]):
    global last_known_status
    last_known_status = status
    msg = f"event: status\ndata: {json.dumps(status, ensure_ascii=False)}\n\n"
    with sse_lock:
        dead = []
        for q in sse_subscribers:
            try:
                q.put_nowait(msg)
            except Exception:
                dead.append(q)
        for d in dead:
            sse_subscribers.discard(d)

def status_poller_loop():
    global last_known_status
    last_compare_key = None
    last_position_update = time.time()
    
    while True:
        try:
            status = bridge.get_status()
            p_state = status.get("player_state")
            track = status.get("track")
            vol = status.get("volume")
            shuf = status.get("shuffle")
            rep = status.get("repeat")
            
            # Form comparison signature
            track_id = track.get("id") if track else None
            pos = track.get("position", 0.0) if track else 0.0
            sig = (p_state, vol, shuf, rep, track_id)

            now = time.time()
            # Broadcast if state/track changed or every 1.5s while playing for position sync
            if sig != last_compare_key or (p_state == "playing" and (now - last_position_update) >= 1.5):
                last_compare_key = sig
                last_position_update = now
                broadcast_status(status)
        except Exception as e:
            print(f"[Poller] Error: {e}")
        time.sleep(0.75)


class RemoteHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Silence verbose standard logging, log errors only
        pass

    def send_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_cors_headers()
        self.end_headers()

    def _send_json(self, data: Any, status: int = 200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_cors_headers()
        self.end_headers()
        self.wfile.write(body)

    def _read_json_body(self) -> Dict[str, Any]:
        try:
            length = int(self.headers.get("Content-Length", 0))
            if length > 0:
                raw = self.rfile.read(length).decode("utf-8")
                return json.loads(raw)
        except Exception:
            pass
        return {}

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        params = urllib.parse.parse_qs(parsed.query)

        # 1. API: Server Info
        if path == "/api/info":
            config = load_config()
            ips = get_lan_ips()
            port = config.get("port", 8080)
            urls = [f"http://{ip}:{port}" for ip in ips]
            self._send_json({
                "status": "ok",
                "port": port,
                "ips": ips,
                "primary_url": urls[0],
                "urls": urls,
                "country": config.get("country", "ru"),
                "hostname": socket.gethostname()
            })
            return

        # 2. API: QR Code
        if path == "/api/qrcode":
            config = load_config()
            ips = get_lan_ips()
            port = config.get("port", 8080)
            remote_url = f"http://{ips[0]}:{port}"
            svg = generate_qr_svg(remote_url, size=320)
            body = svg.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "image/svg+xml")
            self.send_header("Content-Length", str(len(body)))
            self.send_cors_headers()
            self.end_headers()
            self.wfile.write(body)
            return

        # 3. API: Status
        if path == "/api/status":
            status = bridge.get_status()
            self._send_json(status)
            return

        # 4. API: Server-Sent Events (SSE)
        if path == "/api/events":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.send_cors_headers()
            self.end_headers()

            client_queue = queue.Queue(maxsize=30)
            with sse_lock:
                sse_subscribers.add(client_queue)

            # Send initial status immediately
            initial_status = bridge.get_status()
            try:
                self.wfile.write(f"event: status\ndata: {json.dumps(initial_status, ensure_ascii=False)}\n\n".encode("utf-8"))
                self.wfile.flush()
            except Exception:
                with sse_lock:
                    sse_subscribers.discard(client_queue)
                return

            last_ping = time.time()
            try:
                while True:
                    try:
                        msg = client_queue.get(timeout=1.0)
                        self.wfile.write(msg.encode("utf-8"))
                        self.wfile.flush()
                    except queue.Empty:
                        pass

                    now = time.time()
                    if now - last_ping >= 15.0:
                        last_ping = now
                        self.wfile.write(b": ping\n\n")
                        self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
            finally:
                with sse_lock:
                    sse_subscribers.discard(client_queue)
            return

        # 5. API: Artwork
        if path == "/api/artwork":
            track_id = params.get("track_id", [None])[0]
            data = bridge.get_artwork(track_id)
            if data:
                self.send_response(200)
                self.send_header("Content-Type", "image/jpeg")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Cache-Control", "public, max-age=3600")
                self.send_cors_headers()
                self.end_headers()
                self.wfile.write(data)
            else:
                self.send_response(404)
                self.send_cors_headers()
                self.end_headers()
            return

        # 6. API: Playlists
        if path == "/api/playlists":
            playlists = bridge.get_playlists()
            self._send_json({"status": "ok", "playlists": playlists})
            return

        # 7. API: Playlist Tracks
        if path == "/api/playlists/tracks":
            pname = params.get("name", [""])[0]
            if not pname:
                self._send_json({"status": "error", "message": "Missing playlist name"}, 400)
                return
            tracks = bridge.get_playlist_tracks(pname)
            self._send_json({"status": "ok", "playlist": pname, "tracks": tracks})
            return

        # 8. API: Search
        if path == "/api/search":
            q = params.get("q", [""])[0]
            source = params.get("source", ["all"])[0]
            config = load_config()
            country = config.get("country", "ru")

            res: Dict[str, Any] = {"query": q, "results": []}
            if source in ("all", "library"):
                lib_results = bridge.search_library(q)
                res["library"] = lib_results
            if source in ("all", "cloud"):
                cloud_results = bridge.search_cloud(q, country=country)
                res["cloud"] = cloud_results

            self._send_json({"status": "ok", "data": res})
            return

        # 9. API: Explore (Главное / Обзор)
        if path == "/api/explore":
            config = load_config()
            country = config.get("country", "ru")
            explore_data = bridge.get_explore_feed(country=country)
            self._send_json({"status": "ok", "data": explore_data})
            return

        # 10. API: Settings
        if path == "/api/settings":
            config = load_config()
            self._send_json({"status": "ok", "settings": config})
            return

        # Static files from web directory
        web_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "web")
        req_file = path.lstrip("/") or "index.html"
        full_path = os.path.join(web_dir, req_file)

        if os.path.exists(full_path) and os.path.isfile(full_path):
            content_type = "text/html; charset=utf-8"
            if req_file.endswith(".css"):
                content_type = "text/css; charset=utf-8"
            elif req_file.endswith(".js"):
                content_type = "application/javascript; charset=utf-8"
            elif req_file.endswith(".svg"):
                content_type = "image/svg+xml"
            elif req_file.endswith(".png"):
                content_type = "image/png"
            elif req_file.endswith(".json"):
                content_type = "application/json"

            with open(full_path, "rb") as f:
                content = f.read()

            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(content)))
            self.send_cors_headers()
            self.end_headers()
            self.wfile.write(content)
        else:
            # Fallback to index.html for SPA routing
            index_path = os.path.join(web_dir, "index.html")
            if os.path.exists(index_path):
                with open(index_path, "rb") as f:
                    content = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(content)))
                self.send_cors_headers()
                self.end_headers()
                self.wfile.write(content)
            else:
                self.send_response(404)
                self.send_cors_headers()
                self.end_headers()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        body = self._read_json_body()

        # Playback controls
        if path == "/api/play":
            ok = bridge.play()
            self._send_json({"status": "ok" if ok else "error"})
            return

        if path == "/api/pause":
            ok = bridge.pause()
            self._send_json({"status": "ok" if ok else "error"})
            return

        if path == "/api/playpause":
            ok = bridge.playpause()
            self._send_json({"status": "ok" if ok else "error"})
            return

        if path == "/api/next":
            ok = bridge.next_track()
            self._send_json({"status": "ok" if ok else "error"})
            return

        if path == "/api/prev":
            ok = bridge.previous_track()
            self._send_json({"status": "ok" if ok else "error"})
            return

        if path == "/api/seek":
            pos = float(body.get("position", 0.0))
            ok = bridge.seek(pos)
            self._send_json({"status": "ok" if ok else "error", "position": pos})
            return

        if path == "/api/volume":
            vol = int(body.get("volume", 50))
            ok = bridge.set_volume(vol)
            self._send_json({"status": "ok" if ok else "error", "volume": vol})
            return

        if path == "/api/shuffle":
            enabled = bool(body.get("enabled", False))
            ok = bridge.set_shuffle(enabled)
            self._send_json({"status": "ok" if ok else "error", "shuffle": enabled})
            return

        if path == "/api/repeat":
            mode = str(body.get("mode", "off"))
            ok = bridge.set_repeat(mode)
            self._send_json({"status": "ok" if ok else "error", "repeat": mode})
            return

        if path == "/api/play/track":
            track_id = str(body.get("track_id", ""))
            ok = bridge.play_track(track_id)
            self._send_json({"status": "ok" if ok else "error", "track_id": track_id})
            return

        if path == "/api/play/playlist":
            pname = str(body.get("playlist", ""))
            t_idx = body.get("track_index")
            t_idx_int = int(t_idx) if t_idx is not None else None
            t_id = str(body.get("track_id", "")) if body.get("track_id") else None
            ok = bridge.play_playlist(pname, t_idx_int, t_id)
            self._send_json({"status": "ok" if ok else "error", "playlist": pname, "track_id": t_id})
            return

        if path == "/api/play/cloud":
            url = str(body.get("url", ""))
            name = str(body.get("name", "")) if body.get("name") else None
            artist = str(body.get("artist", "")) if body.get("artist") else None
            ok = bridge.play_cloud_url(url, track_name=name, artist_name=artist)
            self._send_json({"status": "ok" if ok else "error", "url": url})
            return

        if path == "/api/settings":
            success, res = save_config(body)
            if success:
                self._send_json({"status": "ok", "settings": res})
            else:
                self._send_json({"status": "error", "message": str(res)}, 500)
            return

        self.send_response(404)
        self.send_cors_headers()
        self.end_headers()


def run_server(port: int = None):
    import signal

    config = load_config()
    server_port = port or config.get("port", 8080)

    # Start poller thread
    poller = threading.Thread(target=status_poller_loop, daemon=True)
    poller.start()

    server_address = ("0.0.0.0", server_port)
    try:
        ThreadingHTTPServer.allow_reuse_address = True
        httpd = ThreadingHTTPServer(server_address, RemoteHandler)
        ips = get_lan_ips()
        print(f"[Server] Apple Music Remote started on port {server_port}")
        for ip in ips:
            print(f"[Server] -> Touch Web Remote: http://{ip}:{server_port}")

        def handle_signal(sig, frame):
            print("\n[Server] Stopping Apple Music Remote server...")
            threading.Thread(target=httpd.shutdown).start()
            sys.exit(0)

        signal.signal(signal.SIGINT, handle_signal)
        signal.signal(signal.SIGTERM, handle_signal)

        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[Server] Interrupted, exiting cleanly...")
        sys.exit(0)
    except Exception as e:
        print(f"[Server] Failed to start server on port {server_port}: {e}")
        sys.exit(1)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Apple Music Remote Server")
    parser.add_argument("--port", type=int, default=None, help="Port to run server on")
    args = parser.parse_args()
    run_server(args.port)
