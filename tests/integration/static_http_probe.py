"""Wire-level static contract assertions, invoked by HTTPIntegrationTests (XCTest)."""
import concurrent.futures
import email.utils
import http.client
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time


def main():
    port = int(sys.argv[1])
    root = Path(tempfile.mkdtemp(prefix="issue30-", dir="public"))
    path = "/static/" + root.name + "/asset.css"
    asset = root / "asset.css"
    payload = b"body { color: blue; }\n"
    stamp = int(time.time()) - 120
    asset.write_bytes(payload)
    os.utime(asset, (stamp, stamp))
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    checks = 0

    def request(headers=None, method="GET", target=path, status=200, body=None):
        nonlocal checks
        if body is None:
            body = payload
        conn.request(method, target, headers=headers or {})
        response = conn.getresponse()
        data = response.read()
        fields = dict((k.lower(), v) for k, v in response.getheaders())
        assert response.status == status, (headers, response.status, fields, data)
        # Static responses bypass middleware but still carry the baseline
        # security headers (GitHub issue 81), including 304/206/416/404.
        assert fields.get("x-content-type-options") == "nosniff", (status, fields)
        assert fields.get("x-frame-options") == "SAMEORIGIN", (status, fields)
        assert "content-security-policy" in fields, (status, fields)
        assert data == body, (headers, data, body)
        if method != "HEAD" and status != 304:
            assert int(fields["content-length"]) == len(body), fields
        if status == 304:
            assert "content-length" not in fields, fields
        checks += 1
        return fields

    try:
        # First static transfer is a nonzero-offset range, exercising injected fallback.
        first = request({"Range": "bytes=7-11"}, status=206, body=payload[7:12])
        assert first["content-range"] == f"bytes 7-11/{len(payload)}"
        headers = request()
        tag, modified = headers["etag"], headers["last-modified"]
        assert tag.startswith('W/"') and tag.endswith('"'), tag
        assert email.utils.parsedate_to_datetime(modified).timestamp() == stamp
        assert headers["content-type"].startswith("text/css"), headers
        assert headers["accept-ranges"] == "bytes"
        head = request(method="HEAD", body=b"")
        for key in ("etag", "last-modified", "content-length", "content-type", "accept-ranges"):
            assert head[key] == headers[key], (key, head, headers)
        older = email.utils.formatdate(stamp - 1, usegmt=True)
        later = email.utils.formatdate(stamp + 1, usegmt=True)
        for method in ("GET", "HEAD"):
            full_body = payload if method == "GET" else b""
            for condition in ({"If-None-Match": tag}, {"If-None-Match": tag[2:]},
                              {"If-None-Match": '"comma,inside", ' + tag},
                              {"If-None-Match": "*"}, {"If-Modified-Since": modified},
                              {"If-Modified-Since": later},
                              {"If-None-Match": tag, "If-Modified-Since": older}):
                result = request(condition, method, status=304, body=b"")
                assert result["etag"] == tag and result["last-modified"] == modified
            for condition in ({"If-None-Match": '"no-match"'},
                              {"If-None-Match": '"no-match"', "If-Modified-Since": later},
                              {"If-Modified-Since": older}, {"If-Modified-Since": "invalid"},
                              {"If-Modified-Since": modified + " junk"},
                              {"If-Modified-Since": modified + ", " + modified}):
                request(condition, method, body=full_body)
        for spec, start, end in (("0-3", 0, 4), ("7-", 7, len(payload)),
                                 ("-4", len(payload)-4, len(payload)),
                                 ("0-999", 0, len(payload)), ("-999", 0, len(payload))):
            result = request({"Range": "bytes=" + spec}, status=206, body=payload[start:end])
            assert result["content-range"] == f"bytes {start}-{end-1}/{len(payload)}"
        for spec in ("bytes=999-", "bytes=-0"):
            result = request({"Range": spec}, status=416, body=b"")
            assert result["content-range"] == f"bytes */{len(payload)}"
        for spec in ("bytes=4-2", "bytes=abc", "bytes=0-1,4-5", "items=0-3",
                     "bytes=18446744073709551616-", "bytes=", "bytes=0-+3"):
            result = request({"Range": spec})
            assert "content-range" not in result
        request({"Range": "bytes=0-3"}, method="HEAD", body=b"")
        request({"Range": "bytes=0-3", "If-None-Match": tag}, status=304, body=b"")
        request({"Range": "bytes=999-", "If-Modified-Since": modified}, status=304, body=b"")
        for validator in (tag, tag[2:], '"no-match"', older, later, "invalid"):
            request({"Range": "bytes=0-3", "If-Range": validator})
        request({"Range": "bytes=0-3", "If-Range": modified}, status=206, body=payload[:4])
        request({"If-Match": "*"})
        request({"If-Match": tag}, status=412, body=b"")
        request({"If-Match": '"no-match"', "If-None-Match": tag}, status=412, body=b"")
        request({"If-Unmodified-Since": older}, status=412, body=b"")
        request({"If-Match": "*", "If-Unmodified-Since": older})
        request({"If-Unmodified-Since": modified})
        # Exercise the same keep-alive connection after 304, HEAD, 416 and 206.
        request()
        # Access checks and canonical redirects precede conditional evaluation.
        base = "/static/" + root.name
        (root / "index.html").write_text("index\n")
        (root / "private.secret").write_text("secret\n")
        (root / "link.css").symlink_to(asset.resolve())
        for target in (base + "/missing.css", base + "/private.secret",
                       base + "/link.css", base + "/../sample.txt"):
            denied = request({"If-None-Match": "*", "Range": "bytes=0-1"},
                             target=target, status=404, body=b"not found\n")
            assert "etag" not in denied
        for target in (base, base + "/index.html"):
            redirect = request({"If-None-Match": "*"}, target=target,
                               status=301, body=b"moved permanently\n")
            assert redirect["location"] == base + "/"
        # Default-allowed extensions carry specific Content-Types (GitHub issue 57).
        for name, expected in (("font.woff2", "font/woff2"), ("image.webp", "image/webp"),
                               ("icon.ico", "image/x-icon"), ("anim.gif", "image/gif")):
            (root / name).write_bytes(b"\x00\x01binary")
            typed = request(target=base + "/" + name, body=b"\x00\x01binary")
            assert typed["content-type"] == expected, (name, typed)
        old_tag = tag
        payload = b"body { color: pink; }\n"  # same length, changed in the same second
        asset.write_bytes(payload)
        os.utime(asset, ns=(stamp * 10**9, stamp * 10**9 + 1000000))
        changed = request({"If-None-Match": old_tag})
        assert changed["etag"] != old_tag
        replacement = root / "replacement.css"
        replacement.write_bytes(b"replacement\n")
        os.utime(replacement, (stamp, stamp))
        replacement.replace(asset)
        payload = b"replacement\n"
        request({"If-None-Match": changed["etag"]})
        asset.write_bytes(b"")
        payload = b""
        request()
        request(method="HEAD", body=b"")
        request({"Range": "bytes=0-0"}, status=416, body=b"")
        # Fresh dates cannot authorize If-Range; future mtimes are capped at Date.
        payload = b"fresh"
        asset.write_bytes(payload)
        os.utime(asset, (time.time()+3600, time.time()+3600))
        fresh = request()
        assert fresh["last-modified"] == fresh["date"]
        request({"Range": "bytes=0-1", "If-Range": fresh["last-modified"]})
        # Concurrent reads must not share a seek position in the fd-cache fallback.
        payload = bytes(range(256)) * 2048
        asset.write_bytes(payload)
        def parallel_range(i):
            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
            start, end = i * 173, i * 173 + 32767
            try:
                connection.request("GET", path, headers={"Range": f"bytes={start}-{end}"})
                response = connection.getresponse()
                assert response.status == 206
                assert response.read() == payload[start:end+1]
            finally:
                connection.close()
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
            list(executor.map(parallel_range, range(24)))
        print(f"static HTTP contract: {checks} sequential checks and 24 concurrent ranges passed")
    finally:
        conn.close()
        shutil.rmtree(root)


if __name__ == "__main__":
    main()
