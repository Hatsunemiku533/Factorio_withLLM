"""Local web front for the shared board. Stdlib only, listens on 127.0.0.1."""

import json
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

import board_store

PORT = 18930
HTML = Path(__file__).with_name("board_web.html")


def read_messages():
    try:
        return {"ok": True, "messages": board_store.recent(50)}
    except ValueError as exc:
        return {"ok": False, "error": str(exc)}


class Handler(BaseHTTPRequestHandler):
    server_version = "MiraBoard/0.1"

    def _send_json(self, payload, status=200):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/":
            body = HTML.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif path == "/api/messages":
            self._send_json(read_messages())
        else:
            self.send_error(404)

    def do_POST(self):
        if urlparse(self.path).path != "/api/post":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length") or 0)
        if length > 8000:
            self._send_json({"ok": False, "error": "request too large"}, 413)
            return
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            message = board_store.post("stellan", str(payload.get("to", "mira")), str(payload.get("text", "")))
            self._send_json({"ok": True, "message": message})
        except (ValueError, KeyError, json.JSONDecodeError) as exc:
            self._send_json({"ok": False, "error": str(exc)}, 400)

    def log_message(self, format, *args):
        pass


def main():
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    webbrowser.open(f"http://127.0.0.1:{PORT}/")
    print(f"Mira board: http://127.0.0.1:{PORT}/  (Ctrl+C to stop)")
    server.serve_forever()


if __name__ == "__main__":
    main()
