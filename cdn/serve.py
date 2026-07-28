"""CDN 探针用的最小静态服务器:带 CORS 头,固定 127.0.0.1:8099,只服务本目录。"""
import http.server
import os
import socketserver

os.chdir(os.path.dirname(os.path.abspath(__file__)))


class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("127.0.0.1", 8099), H) as s:
    print("serving cdn on http://127.0.0.1:8099", flush=True)
    s.serve_forever()
