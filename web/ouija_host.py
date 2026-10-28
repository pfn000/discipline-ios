#!/usr/bin/env python3
"""Ouija ring sign-in helper.

Run it on the computer you want to sign in to, on the same Wi-Fi as your iPhone:

    python3 ouija_host.py            # serves this folder on port 8737 and advertises it to Ouija

then open http://localhost:8737 in your browser (localhost counts as a secure page, which the
browser needs to make the Ed25519 key). Ouija finds this computer over Bonjour
(_ncom-ouija._tcp), hands it a fresh session string, and the page turns that into rings.

Bonjour: uses the `zeroconf` package if it's installed (pip install zeroconf), otherwise macOS
`dns-sd` or Linux `avahi-publish-service`. Only the Python standard library is required.
Nothing secret passes through here: the session is a one-time challenge and /pubkey is public.
"""
import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

SERVICE = "_ncom-ouija._tcp"
HERE = os.path.dirname(os.path.abspath(__file__))
STATE = {"session": None, "session_at": None, "key": None}
LOCK = threading.Lock()
HEX32 = re.compile(r"^[0-9a-f]{32}$")
KEY = re.compile(r"^NCOMKEY1\.[A-Za-z0-9_-]{43}$")


class Handler(SimpleHTTPRequestHandler):
    server_version = "OuijaHost/1"

    def __init__(self, *a, **kw):
        super().__init__(*a, directory=HERE, **kw)

    def log_message(self, fmt, *args):
        if self.path.startswith(("/session", "/pubkey")) and self.command == "POST":
            sys.stderr.write("  %s %s\n" % (self.command, self.path))

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        super().end_headers()

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0 or n > 4096:
            return None
        try:
            return json.loads(self.rfile.read(n))
        except ValueError:
            return None

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/health":
            return self._json(200, {"service": "ouija-host", "name": self.server.display_name})
        if path == "/session":
            with LOCK:
                return self._json(200, {"session": STATE["session"], "at": STATE["session_at"]})
        if path == "/pubkey":
            with LOCK:
                return self._json(200 if STATE["key"] else 404, {"key": STATE["key"]})
        if path.endswith(".py"):
            return self._json(404, {"error": "not found"})
        return super().do_GET()

    def do_POST(self):
        path = self.path.split("?")[0]
        body = self._body() or {}
        if path == "/session":
            s = str(body.get("session", "")).lower()
            if not HEX32.match(s):
                return self._json(400, {"error": "session must be 32 hex characters"})
            with LOCK:
                STATE["session"], STATE["session_at"] = s, int(time.time())
            print("Ouija handed over a session %s… — the page is showing the rings." % s[:8], flush=True)
            return self._json(200, {"ok": True})
        if path == "/pubkey":
            k = str(body.get("key", ""))
            if not KEY.match(k):
                return self._json(400, {"error": "key must be NCOMKEY1.<43 base64url characters>"})
            with LOCK:
                STATE["key"] = k
            return self._json(200, {"ok": True})
        return self._json(404, {"error": "not found"})


def advertise(name, port):
    """Returns a stop() function. Tries zeroconf, then dns-sd, then avahi."""
    try:
        from zeroconf import ServiceInfo, Zeroconf  # type: ignore
        ip = local_ip()
        info = ServiceInfo(SERVICE + ".local.", "%s.%s.local." % (name, SERVICE), port=port,
                           addresses=[socket.inet_aton(ip)], properties={"v": "1"})
        zc = Zeroconf()
        zc.register_service(info)
        return "zeroconf", lambda: (zc.unregister_service(info), zc.close())
    except Exception:
        pass
    for cmd in (["dns-sd", "-R", name, SERVICE, "local", str(port), "v=1"],
                ["avahi-publish-service", name, SERVICE, str(port), "v=1"]):
        if shutil.which(cmd[0]):
            p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return cmd[0], p.terminate
    return None, lambda: None


def local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def main():
    ap = argparse.ArgumentParser(description="Serve the Ouija ring page and let Ouija find this computer.")
    ap.add_argument("--port", type=int, default=8737)
    ap.add_argument("--name", default=socket.gethostname().split(".")[0] or "Computer")
    ap.add_argument("--no-bonjour", action="store_true", help="serve the page only")
    a = ap.parse_args()
    srv = ThreadingHTTPServer(("0.0.0.0", a.port), Handler)
    srv.display_name = a.name
    how, stop = (None, lambda: None) if a.no_bonjour else advertise(a.name, a.port)
    print("Ouija ring page: http://localhost:%d" % a.port)
    if how:
        print("Ouija can find “%s” on this Wi-Fi (Bonjour via %s)." % (a.name, how))
    elif not a.no_bonjour:
        print("No Bonjour here: pip install zeroconf (or use Bluetooth in Chrome/Edge).")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        stop()
        srv.server_close()


if __name__ == "__main__":
    main()
