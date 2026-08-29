#!/usr/bin/env python3
import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs
from urllib.request import Request, urlopen

UPSTREAM = os.environ.get("UDM_VOIP_XML_UPSTREAM", "http://127.0.0.1:3423")
HOST = os.environ.get("UDM_VOIP_XML_PROXY_HOST", "127.0.0.1")
PORT = int(os.environ.get("UDM_VOIP_XML_PROXY_PORT", "3424"))
ACL_RANGES = os.environ.get("UDM_VOIP_TALK_ACL_RANGES", "").split()


def patch_acl(xml: str) -> str:
    if 'list name="talk_acl"' not in xml:
        return xml
    missing = [cidr for cidr in ACL_RANGES if f'cidr="{cidr}"' not in xml]
    if not missing:
        return xml
    nodes = ''.join(f'<node type="allow" cidr="{cidr}"></node>' for cidr in missing)
    return re.sub(r'(<list name="talk_acl"[^>]*>)', r'\1' + nodes, xml, count=1)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print("[udm-voip-acl] " + (fmt % args), flush=True)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        req = Request(
            UPSTREAM + self.path,
            data=body,
            method="POST",
            headers={
                "Content-Type": self.headers.get("Content-Type", "application/x-www-form-urlencoded"),
                "User-Agent": self.headers.get("User-Agent", "freeswitch-xml/1.0"),
            },
        )
        try:
            response = urlopen(req, timeout=10)
            status = response.status
            data = response.read()
            content_type = response.headers.get("Content-Type", "text/plain")
        except HTTPError as exc:
            status = exc.code
            data = exc.read()
            content_type = exc.headers.get("Content-Type", "text/plain")
        except URLError as exc:
            status = 502
            data = str(exc).encode()
            content_type = "text/plain"

        params = parse_qs(body.decode("utf-8", errors="ignore"))
        if (
            status == 200
            and self.path == "/api/pbx/configuration"
            and params.get("key_value", [""])[0] == "acl.conf"
        ):
            data = patch_acl(data.decode("utf-8", errors="replace")).encode("utf-8")

        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
