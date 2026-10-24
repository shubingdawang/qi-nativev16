"""3D 小岛的本地预览：在 Qi/Resources/Island3D 上开一个不缓存的小服务器（改了脚本刷新就是新的）。

用法：python scripts/island3d_preview.py [端口]，然后浏览器打开 http://localhost:端口/
  ?app=1        假装在 App 里（能走、能转视角，岛的数据用 island.json）
  ?gallery=1    把每一种景排成一排排看
"""
import http.server
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Qi", "Resources", "Island3D")


class NoCache(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=ROOT, **k)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8767
    http.server.ThreadingHTTPServer(("", port), NoCache).serve_forever()
