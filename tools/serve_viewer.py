"""Serves viewer/ for the combinations viewer: a plain static server that tells the browser never to reuse a stale copy
(the data and the pictures are rebuilt often).
    python tools/serve_viewer.py PORT [--bind 127.0.0.1] [--directory DIR]
"""
import argparse
import functools
import http.server
import os


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache, must-revalidate')
        super().end_headers()

    def log_message(self, fmt, *args):
        pass


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument('port', type=int)
    ap.add_argument('--bind', default='127.0.0.1')
    ap.add_argument('--directory', default=os.path.join(os.path.dirname(here), 'viewer'))
    a = ap.parse_args()
    handler = functools.partial(Handler, directory=a.directory)
    with http.server.ThreadingHTTPServer((a.bind, a.port), handler) as srv:
        print('serving %s on http://%s:%d/' % (a.directory, a.bind, a.port), flush=True)
        srv.serve_forever()


if __name__ == '__main__':
    main()
