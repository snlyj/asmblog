#!/usr/bin/env python3
import concurrent.futures
import hashlib
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = os.path.join(ROOT, "asmblog")
SITE = os.path.join(ROOT, "site")
PORT = 18080
BASE = f"http://127.0.0.1:{PORT}"


def assert_eq(a, b, msg=""):
    if a != b:
        raise AssertionError(f"{msg}: expected {b!r}, got {a!r}")


def http_req(path, method="GET", headers=None, data=None):
    req = urllib.request.Request(BASE + path, method=method, headers=headers or {}, data=data)
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status, dict(resp.headers), resp.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read()


def raw_exchange(chunks):
    s = socket.create_connection(("127.0.0.1", PORT), timeout=5)
    try:
        for i, ch in enumerate(chunks):
            s.sendall(ch)
            if i + 1 < len(chunks):
                time.sleep(0.03)
        data = b""
        while True:
            part = s.recv(65536)
            if not part:
                break
            data += part
        return data
    finally:
        s.close()


def read_rss_kb(pid):
    with open(f"/proc/{pid}/status") as f:
        for line in f:
            if line.startswith("VmRSS:"):
                return int(line.split()[1])
    return 0


def count_fds(pid):
    return len(os.listdir(f"/proc/{pid}/fd"))


def test_elf():
    out = subprocess.check_output(["file", BIN], text=True)
    assert "x86-64" in out and "statically linked" in out, f"unexpected file output: {out}"
    re_out = subprocess.check_output(["readelf", "-d", BIN], text=True)
    assert "NEEDED" not in re_out, f"unexpected dynamic deps: {re_out}"
    print("[PASS] ELF static zero-libc check")


def test_cli_init_new_build():
    r = subprocess.run([BIN, "--version"], capture_output=True, text=True, check=True)
    assert "AsmBlog" in r.stdout
    r = subprocess.run([BIN, "--help"], capture_output=True, text=True, check=True)
    assert "asmblog build" in r.stdout and "hash-pass" in r.stdout

    # Verify pure-asm hash-pass CLI matches hashlib.sha256 bit-for-bit
    hp = subprocess.run([BIN, "hash-pass", "test-pass-2026"], capture_output=True, text=True, check=True)
    expected_hash = hashlib.sha256(b"test-pass-2026").hexdigest()
    assert f"studio_pass_sha256 = {expected_hash}" in hp.stdout, f"unexpected hash-pass output: {hp.stdout!r}"

    tmp = tempfile.mkdtemp(prefix="asmblog_init_")
    try:
        subprocess.run([BIN, "init", tmp], check=True, capture_output=True, text=True)
        assert os.path.isfile(os.path.join(tmp, "config.ini"))
        assert os.path.isfile(os.path.join(tmp, "content/posts/hello-world.md"))

        subprocess.run([BIN, "new", "cli-test-post", "CLI Post Title", "-d", tmp], check=True, capture_output=True, text=True)
        new_md = os.path.join(tmp, "content/posts/cli-test-post.md")
        assert os.path.isfile(new_md)
        txt = open(new_md, encoding="utf-8").read()
        assert 'title: "CLI Post Title"' in txt
        assert "slug: cli-test-post" in txt

        # Reject invalid slug
        bad = subprocess.run([BIN, "new", "../evil", "-d", tmp], capture_output=True, text=True)
        assert bad.returncode != 0, "invalid slug should fail"

        # Build static site in temp init dir
        res = subprocess.run([BIN, "build", "-d", tmp], check=True, capture_output=True, text=True)
        assert "built static site" in res.stdout
        for rel in [
            "dist/index.html",
            "dist/page/1/index.html",
            "dist/post/hello-world/index.html",
            "dist/post/cli-test-post/index.html",
            "dist/archive/index.html",
            "dist/tags/index.html",
            "dist/search/index.html",
            "dist/search-index.json",
            "dist/rss.xml",
            "dist/sitemap.xml",
            "dist/404.html",
            "dist/favicon.ico",
            "dist/static/style.css",
            "dist/static/app.js",
        ]:
            p = os.path.join(tmp, rel)
            assert os.path.isfile(p) and os.path.getsize(p) > 0, f"missing/empty {rel}"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("[PASS] CLI init / new / build / slug validation")


def test_site_ssg_build():
    dist_tmp = os.path.join(SITE, "dist_test")
    shutil.rmtree(dist_tmp, ignore_errors=True)
    try:
        res = subprocess.run([BIN, "build", "-d", SITE, "-o", "dist_test"], check=True, capture_output=True, text=True)
        assert "3 posts" in res.stdout, res.stdout

        idx_html = open(os.path.join(dist_tmp, "index.html"), encoding="utf-8").read()
        assert "欢迎使用 AsmBlog" in idx_html
        assert "零 libc 架构解析" in idx_html

        # Chinese tag & category directories generated cleanly
        cn_tag_html = os.path.join(dist_tmp, "tag", "静态博客", "index.html")
        assert os.path.isfile(cn_tag_html), "UTF-8 tag page missing"
        cn_cat_html = os.path.join(dist_tmp, "category", "日常随笔", "index.html")
        assert os.path.isfile(cn_cat_html), "UTF-8 category page missing"

        # Valid JSON search index
        sidx = json.loads(open(os.path.join(dist_tmp, "search-index.json"), encoding="utf-8").read())
        assert_eq(len(sidx), 3, "search-index count")

        # Valid XML for RSS and Sitemap
        rss = ET.fromstring(open(os.path.join(dist_tmp, "rss.xml"), encoding="utf-8").read())
        assert len(rss.findall(".//item")) == 3
        sm = ET.fromstring(open(os.path.join(dist_tmp, "sitemap.xml"), encoding="utf-8").read())
        assert len(list(sm)) == 4  # home + 3 posts

        # Copied static assets
        assert os.path.getsize(os.path.join(dist_tmp, "static/sky-ribbon.css")) > 500
        assert os.path.getsize(os.path.join(dist_tmp, "static/sky-ribbon.js")) > 300
    finally:
        shutil.rmtree(dist_tmp, ignore_errors=True)
    print("[PASS] Main site SSG build (HTML, UTF-8 tags, JSON, RSS XML, Sitemap XML, static copy)")


def test_server():
    test_pass = "studio-ci-pass-2026"
    test_hash = hashlib.sha256(test_pass.encode()).hexdigest()
    tmp_cfg_fd, tmp_cfg_path = tempfile.mkstemp(prefix="asmblog_cfg_", suffix=".ini")
    os.close(tmp_cfg_fd)
    with open(tmp_cfg_path, "w", encoding="utf-8") as cf:
        cf.write(
            "site_name = SkyRibbon Blog\n"
            "subtitle = Pure x86-64 Assembly Anime Static Blog ✦\n"
            "site_url = http://127.0.0.1:18080\n"
            "author = Sakura\n"
            "footer_text = Made with ♡ · Pure x86-64 Assembly\n"
            "avatar_url = /static/avatar.webp?v=3&orig=/static/avatar.jpg\n"
            "banner_url = /static/hero-banner.webp?v=3&orig=/static/hero-banner.jpg\n"
            f"port = {PORT}\n"
            "per_page = 6\n"
            "theme = sky-ribbon\n"
            "dist_dir = dist\n"
            "studio_path = /studio\n"
            f"studio_pass_sha256 = {test_hash}\n"
        )

    proc = subprocess.Popen(
        [BIN, "serve", "-d", SITE, "-c", tmp_cfg_path, "-p", str(PORT)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    temp_files = [tmp_cfg_path, tmp_cfg_path + ".tmp"]
    try:
        # Wait for startup
        for _ in range(40):
            try:
                st, _, _ = http_req("/healthz")
                if st == 200:
                    break
            except Exception:
                time.sleep(0.05)
        else:
            raise RuntimeError("server failed to start")

        # 1. Core GET routes (with & without trailing slash)
        routes = [
            "/",
            "/page/1",
            "/page/1/",
            "/post/welcome-to-asmblog",
            "/post/welcome-to-asmblog/",
            "/post/x86-64-assembly-architecture/",
            "/archive",
            "/archive/",
            "/tags",
            "/tags/",
            "/tag/asmblog/",
            "/tag/" + urllib.parse.quote("静态博客") + "/",
            "/search?q=assembly",
            "/search-index.json",
            "/rss.xml",
            "/sitemap.xml",
            "/healthz",
            "/static/sky-ribbon.css",
            "/static/sky-ribbon.js",
            "/static/hero-banner.jpg",
            "/static/hero-banner.webp",
            "/static/avatar.jpg",
            "/static/avatar.webp",
            "/static/notfound.jpg",
            "/static/notfound.webp",
            "/static/favicon-ribbon.svg",
            "/favicon.ico",
        ]
        for r in routes:
            st, hdrs, body = http_req(r)
            assert_eq(st, 200, f"GET {r}")
            assert len(body) > 0, f"empty body for {r}"

        _, _, home_html = http_req("/")
        home_txt = home_html.decode("utf-8")
        assert "SkyRibbon Blog" in home_txt and "Sakura" in home_txt, "site title/author missing"
        assert "Pure x86-64 Assembly Anime Static Blog" in home_txt, "custom subtitle missing"
        assert "footer-pill" in home_txt and "Made with ♡" in home_txt, "footer pill frame or footer_text missing"
        assert "/studio" not in home_txt, "studio must stay hidden from public homepage"
        assert "/static/hero-banner.webp" in home_txt and "/static/avatar.webp" in home_txt, "anime theme WebP preview assets missing"
        assert "orig=/static/hero-banner.jpg" in home_txt and "orig=/static/avatar.jpg" in home_txt, "original HD fallback query missing"

        # Category public page
        st_cat, _, cat_html = http_req("/category/" + urllib.parse.quote("日常随笔") + "/")
        assert_eq(st_cat, 200, "GET /category/日常随笔/")
        assert "欢迎使用 AsmBlog" in cat_html.decode("utf-8"), "category post missing"

        # Check HTML & JSON & XML content
        _, _, search_html = http_req("/search?q=assembly")
        assert "零 libc 架构解析" in search_html.decode("utf-8")

        _, _, idx_json = http_req("/search-index.json")
        assert len(json.loads(idx_json)) == 3

        # 2. HEAD request
        st, hdrs, body = http_req("/", method="HEAD")
        assert_eq(st, 200, "HEAD /")
        assert int(hdrs.get("Content-Length", "0")) > 100
        assert_eq(body, b"", "HEAD body must be empty")

        # 3. Static ETag + RFC-compliant 304 Not Modified + Smart Cache-Control
        st, hdrs, body = http_req("/static/sky-ribbon.css")
        etag = hdrs.get("ETag")
        assert etag and etag.startswith('"'), f"bad ETag: {etag}"
        assert "must-revalidate" in hdrs.get("Cache-Control", ""), f"expected must-revalidate: {hdrs}"
        st304, hdrs304, body304 = http_req("/static/sky-ribbon.css", headers={"If-None-Match": etag})
        assert_eq(st304, 304, "ETag 304")
        assert_eq(body304, b"", "304 body")
        assert "Content-Type" not in hdrs304, f"304 should omit Content-Type: {hdrs304}"
        # RFC 9110 weak comparison: W/ prefix and ETag lists must also match
        st_w, _, _ = http_req("/static/sky-ribbon.css", headers={"If-None-Match": "W/" + etag})
        assert_eq(st_w, 304, "weak If-None-Match 304")
        st_l, _, _ = http_req("/static/sky-ribbon.css", headers={"If-None-Match": '"nope", ' + etag})
        assert_eq(st_l, 304, "If-None-Match list 304")
        st_m, _, _ = http_req("/static/sky-ribbon.css", headers={"If-None-Match": '"nope"'})
        assert_eq(st_m, 200, "mismatched If-None-Match 200")

        # Dynamic pages: content-hash weak ETag + no-cache + 304 revalidation
        for dyn in ("/", "/post/welcome-to-asmblog/", "/archive/", "/rss.xml", "/sitemap.xml", "/search-index.json"):
            st_d, hd, bd = http_req(dyn)
            assert_eq(st_d, 200, f"GET {dyn}")
            dtag = hd.get("ETag", "")
            assert dtag.startswith('W/"') and len(dtag) == 20, f"bad dynamic ETag on {dyn}: {dtag!r}"
            assert "no-cache" in hd.get("Cache-Control", ""), f"dynamic page must be no-cache: {hd}"
            st_d2, hd2, _ = http_req(dyn)
            assert_eq(hd2.get("ETag"), dtag, f"ETag must be stable for {dyn}")
            st_d3, hd3, bd3 = http_req(dyn, headers={"If-None-Match": dtag})
            assert_eq(st_d3, 304, f"dynamic 304 {dyn}")
            assert_eq(bd3, b"", f"dynamic 304 body {dyn}")
            assert hd3.get("ETag") == dtag and "Content-Type" not in hd3, f"bad 304 headers {dyn}: {hd3}"
            st_h, _, bh = http_req(dyn, method="HEAD", headers={"If-None-Match": dtag})
            assert_eq(st_h, 304, f"HEAD dynamic 304 {dyn}")
        _, hd_a, _ = http_req("/")
        _, hd_b, _ = http_req("/archive/")
        assert hd_a["ETag"] != hd_b["ETag"], "different pages must have different ETags"
        _, hz_h, _ = http_req("/healthz")
        assert "ETag" not in hz_h and "no-store" in hz_h.get("Cache-Control", ""), f"healthz must not be cached: {hz_h}"
        st_404, hd_404, _ = http_req("/does-not-exist", headers={"If-None-Match": "*"})
        assert_eq(st_404, 404, "404 must ignore If-None-Match")

        st_imm, hdrs_imm, css_v14 = http_req("/static/sky-ribbon.css?v=14")
        assert_eq(st_imm, 200, "versioned static css 200")
        assert "immutable" in hdrs_imm.get("Cache-Control", ""), f"expected immutable on versioned URL: {hdrs_imm}"
        css_rules = re.sub(rb"/\*[\s\S]*?\*/", b"", css_v14)
        for forbidden in (b"100dvh", b"backdrop-filter", b"filter: blur", b"position: sticky"):
            assert forbidden not in css_rules, f"forbidden jank CSS rule found: {forbidden!r}"
        for required_css in (b"hover: hover", b".lightbox", b".lightbox-badge", b".prose-video", b".pjax-loader", b".post-grid", b".toc-desktop", b".toc-mobile", b".toc-sheet", b".article-fabs", b".cmd-modal", b".font-size-ctrl", b".sky-toast", b".search-hl", b".archive-year", b".comments-card"):
            assert required_css in css_rules, f"missing expected UI CSS rule: {required_css!r}"

        st_js, _, js_v14 = http_req("/static/sky-ribbon.js?v=14")
        assert_eq(st_js, 200, "versioned static js 200")
        for required_js in (b"img-lightbox", b"extractOrigUrl", b"loadedOrigs", b"zoomLightboxAt", b"preloadAdjacent", b"enhanceVideos", b"ring-progress", b"pjax-loader", b"initArticleExtras", b"initArchiveYears", b"initComments", b"syncGiscusTheme", b"setLightboxZoom", b"showToast", b"highlightText", b"openCmdSearch", b"openTocSheet", b"applyFontSize", b"scrollMemo", b"touchstart"):
            assert required_js in js_v14, f"missing expected UI JS feature: {required_js!r}"

        # Open Graph / Twitter Card social preview meta + zero-bloat Giscus hidden by default
        assert 'property="og:type" content="website"' in home_txt
        assert 'property="og:image" content="http://127.0.0.1:18080/static/hero-banner.webp?v=3&amp;orig=/static/hero-banner.jpg"' in home_txt
        assert 'name="twitter:card" content="summary_large_image"' in home_txt

        # Verify WebP preview serves with image/webp + immutable cache when query string is attached
        st_wp, hdrs_wp, wp_body = http_req("/static/hero-banner.webp?v=3&orig=/static/hero-banner.jpg")
        assert_eq(st_wp, 200, "GET hero-banner.webp?orig=...")
        assert "image/webp" in hdrs_wp.get("Content-Type", ""), f"bad webp mime: {hdrs_wp}"
        assert "immutable" in hdrs_wp.get("Cache-Control", ""), f"expected immutable on webp preview: {hdrs_wp}"
        assert len(wp_body) < 120000, f"expected compact WebP preview, got {len(wp_body)}B"

        st_post, _, post_html = http_req("/post/welcome-to-asmblog/")
        assert_eq(st_post, 200, "GET /post/welcome-to-asmblog/")
        post_txt = post_html.decode("utf-8")
        assert "article-toc-slot" in post_txt and "share-post-btn" in post_txt, "article TOC/share hooks missing"
        assert 'property="og:type" content="article"' in post_txt
        assert 'property="og:url" content="http://127.0.0.1:18080/post/welcome-to-asmblog/"' in post_txt
        assert "comments-card" not in post_txt, "Giscus comments must stay completely absent when unconfigured"

        # 4. 404 & 405 Read-Only Enforcement
        st, _, _ = http_req("/does-not-exist")
        assert_eq(st, 404, "404 unknown")
        st, _, _ = http_req("/post/no-such-slug/")
        assert_eq(st, 404, "404 post")
        for m in ("POST", "PUT", "DELETE"):
            st, _, _ = http_req("/", method=m)
            assert_eq(st, 405, f"{m} / must be 405")

        # 5. Path traversal & hidden dot-file protection (.gitkeep / .part / ../)
        for bad_path in ["/static/../../etc/passwd", "/static/%2e%2e/%2e%2e/etc/passwd", "/uploads/.gitkeep", "/uploads/.hidden.mp4.part"]:
            raw = raw_exchange([f"GET {bad_path} HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n".encode()])
            assert raw.startswith(b"HTTP/1.1 403"), f"expected 403 for {bad_path}, got {raw[:40]!r}"

        # 6. Malformed HTTP (400) & Oversized URI (414)
        raw400 = raw_exchange([b"GARBAGE\r\n\r\n"])
        assert raw400.startswith(b"HTTP/1.1 400"), f"expected 400, got {raw400[:40]!r}"
        raw414 = raw_exchange([b"GET /" + b"a" * 2200 + b" HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n"])
        assert raw414.startswith(b"HTTP/1.1 414"), f"expected 414, got {raw414[:40]!r}"

        # 7. Split-packet TCP delivery + HTTP/1.1 Keep-Alive reuse
        s = socket.create_connection(("127.0.0.1", PORT), timeout=5)
        try:
            for i in range(5):
                req_b = b"GET /healthz HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n"
                if i == 0:
                    s.sendall(req_b[:15])
                    time.sleep(0.02)
                    s.sendall(req_b[15:])
                else:
                    s.sendall(req_b)
                buf = b""
                while b"\r\n\r\n" not in buf:
                    buf += s.recv(4096)
                hdr_part, rest = buf.split(b"\r\n\r\n", 1)
                assert b"200 OK" in hdr_part and b"keep-alive" in hdr_part.lower()
                cl = 0
                for line in hdr_part.split(b"\r\n"):
                    if line.lower().startswith(b"content-length:"):
                        cl = int(line.split(b":", 1)[1].strip())
                while len(rest) < cl:
                    rest += s.recv(4096)
                assert json.loads(rest[:cl])["status"] == "ok"
            # Pipelined burst: 10 requests in ONE single sendall (verifies iterative non-recursive pipeline loop)
            burst = b"GET /healthz HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n" * 10
            s.sendall(burst)
            pbuf = b""
            for _ in range(10):
                while b"\r\n\r\n" not in pbuf:
                    pbuf += s.recv(65536)
                h, pbuf = pbuf.split(b"\r\n\r\n", 1)
                assert b"200 OK" in h
                cl = 0
                for line in h.split(b"\r\n"):
                    if line.lower().startswith(b"content-length:"):
                        cl = int(line.split(b":", 1)[1].strip())
                while len(pbuf) < cl:
                    pbuf += s.recv(65536)
                body_p, pbuf = pbuf[:cl], pbuf[cl:]
                assert json.loads(body_p)["status"] == "ok"
        finally:
            s.close()
        print("[PASS] HTTP routes, HEAD, ETag/304, Cache-Control, 404/405, 403, 400/414, split TCP, Keep-Alive & 10x Pipeline")

        # 8. inotify Hot-Reload + Draft Hiding + XSS Neutralization
        _, _, hz1 = http_req("/healthz")
        r1 = json.loads(hz1)["reloads"]

        hot_md = os.path.join(SITE, "content/posts/__hot_test.md")
        draft_md = os.path.join(SITE, "content/posts/__draft_test.md")
        temp_files.extend([hot_md, draft_md])

        with open(hot_md, "w", encoding="utf-8") as f:
            f.write(
                '---\ntitle: "Hot Reload XSS Test"\nslug: hot-reload-test\ndate: 2026-11-24\ntags: hot\ndraft: false\n---\n\n'
                'Raw <script>alert(1)</script> and [evil](javascript:alert(2)) and [safe](https://example.com).\n'
            )
        with open(draft_md, "w", encoding="utf-8") as f:
            f.write(
                '---\ntitle: "Secret Draft"\nslug: secret-draft\ndate: 2026-11-24\ndraft: true\n---\nHidden\n'
            )

        for _ in range(30):
            _, _, hz2 = http_req("/healthz")
            if json.loads(hz2)["reloads"] > r1:
                break
            time.sleep(0.05)

        hz_data = json.loads(http_req("/healthz")[2])
        assert hz_data["reloads"] > r1, "inotify reload did not fire"
        assert_eq(hz_data["published"], 4, "published count after hot add")

        st, _, post_body = http_req("/post/hot-reload-test/")
        assert_eq(st, 200, "hot post 200")
        html = post_body.decode("utf-8")
        assert "<script>alert(1)</script>" not in html and "&lt;script&gt;" in html, "script XSS not escaped!"
        assert "javascript:" not in html, "javascript: URL not stripped!"
        assert 'href="https://example.com"' in html, "safe link broken"

        st_draft, _, _ = http_req("/post/secret-draft/")
        assert_eq(st_draft, 404, "draft post must return 404")

        os.unlink(hot_md)
        os.unlink(draft_md)
        temp_files.remove(hot_md)
        temp_files.remove(draft_md)
        for _ in range(30):
            if json.loads(http_req("/healthz")[2])["published"] == 3:
                break
            time.sleep(0.05)
        assert_eq(json.loads(http_req("/healthz")[2])["published"], 3, "hot delete reload")
        print("[PASS] inotify live hot-reload, draft hiding, and Markdown XSS neutralization")

        # 8b. Hidden Author Studio: Random Token Auth, Settings Hot-Reload, Custom Path, Brute-Force 429, CRUD
        st, hdrs, st_page = http_req("/studio")
        assert_eq(st, 200, "GET /studio")
        assert "no-store" in hdrs.get("Cache-Control", ""), "studio page must be no-store"
        st_txt = st_page.decode("utf-8")
        assert "作者秘密写作室" in st_txt
        assert "crop-modal" in st_txt and "crop-stage" in st_txt and "tab-settings" in st_txt, "studio UI features missing"
        for required_st in ("draft-restore-bar", "upload-progress-wrap", "posts-filter-bar", "studio-theme-btn", "word-count-badge", "data-toggle-draft"):
            assert required_st in st_txt, f"missing Studio UX feature: {required_st}"

        # Must block unauthenticated Studio API requests (including forged raw SHA256 hash cookie!)
        forged_hdr = {"Cookie": f"asmblog_studio={test_hash}"}
        for m, u in [
            ("GET", "/api/studio/posts"),
            ("POST", "/api/studio/posts"),
            ("GET", "/api/studio/categories"),
            ("POST", "/api/studio/categories"),
            ("GET", "/api/studio/settings"),
            ("POST", "/api/studio/settings"),
            ("POST", "/api/studio/upload"),
            ("DELETE", "/api/studio/posts/welcome-to-asmblog"),
        ]:
            st_u, _, _ = http_req(u, method=m, headers=forged_hdr, data=(b"{}" if m == "POST" else None))
            assert_eq(st_u, 401, f"unauth/forged {m} {u} must return 401")

        # Wrong passphrase rejected
        st_bad, _, _ = http_req(
            "/api/studio/login",
            method="POST",
            headers={"Content-Type": "application/json"},
            data=json.dumps({"password": "wrong-password"}).encode(),
        )
        assert_eq(st_bad, 401, "wrong studio password")

        # Correct passphrase succeeds, sets random 64-hex token != sha256(pass), auto-adds Secure over HTTPS
        st_ok, h_ok, _ = http_req(
            "/api/studio/login",
            method="POST",
            headers={"Content-Type": "application/json", "X-Forwarded-Proto": "https"},
            data=json.dumps({"password": test_pass}).encode(),
        )
        assert_eq(st_ok, 200, "studio login 200")
        set_ck = h_ok.get("Set-Cookie", "")
        assert "asmblog_studio=" in set_ck and "HttpOnly" in set_ck and "Secure" in set_ck, f"bad auth cookie: {set_ck}"
        ck_pair = set_ck.split(";", 1)[0]
        tok_val = ck_pair.split("=", 1)[1]
        assert_eq(len(tok_val), 64, "session token length")
        assert tok_val != test_hash, "session token must be random, NOT raw password SHA-256!"
        cookie_hdr = {"Cookie": ck_pair}

        # Reject fake non-image upload
        st_f, _, _ = http_req(
            "/api/studio/upload",
            method="POST",
            headers={**cookie_hdr, "Content-Type": "image/png"},
            data=b"not a real image payload at all!!",
        )
        assert_eq(st_f, 400, "fake image must be rejected")

        # Upload real PNG (1x1 transparent PNG)
        tiny_png = (
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
            b"\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01"
            b"\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82"
        )
        st_up, _, up_body = http_req(
            "/api/studio/upload",
            method="POST",
            headers={**cookie_hdr, "Content-Type": "image/png"},
            data=tiny_png,
        )
        assert_eq(st_up, 201, "valid PNG upload 201")
        up_url = json.loads(up_body)["url"]
        assert up_url.startswith("/uploads/") and up_url.endswith(".png"), f"bad upload url: {up_url}"
        uploaded_disk_path = os.path.join(SITE, "content", up_url.lstrip("/"))
        temp_files.append(uploaded_disk_path)

        st_img, img_hdrs, img_bytes = http_req(up_url)
        assert_eq(st_img, 200, "serve uploaded PNG")
        assert_eq(img_bytes, tiny_png, "uploaded PNG bytes match")
        assert "image/png" in img_hdrs.get("Content-Type", "")
        assert "immutable" in img_hdrs.get("Cache-Control", "")
        assert img_hdrs.get("Accept-Ranges") == "bytes", f"missing Accept-Ranges: {img_hdrs}"

        # Chunked video upload: reject fake non-video & path traversal IDs
        st_fv, _, _ = http_req(
            "/api/studio/upload-video?done=1",
            method="POST",
            headers={**cookie_hdr, "Content-Type": "application/octet-stream"},
            data=b"not a valid video file header!",
        )
        assert_eq(st_fv, 400, "fake video must be rejected")
        st_tv, _, _ = http_req(
            "/api/studio/upload-video?id=../evil.mp4&done=1",
            method="POST",
            headers={**cookie_hdr, "Content-Type": "application/octet-stream"},
            data=b"1234",
        )
        assert_eq(st_tv, 400, "traversal video id must be rejected")

        # Valid 2-chunk MP4 upload (ISO BMFF ftyp header + second chunk)
        vid_c1 = b"\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom" + (b"A" * 64)
        vid_c2 = b"B" * 40
        vid_all = vid_c1 + vid_c2
        st_v1, _, vb1 = http_req(
            "/api/studio/upload-video?done=0",
            method="POST",
            headers={**cookie_hdr, "Content-Type": "application/octet-stream"},
            data=vid_c1,
        )
        assert_eq(st_v1, 200, "video chunk 1 ok")
        vid_id = json.loads(vb1)["id"]
        assert vid_id.endswith(".mp4"), f"unexpected vid_id: {vid_id}"
        st_v2, _, vb2 = http_req(
            f"/api/studio/upload-video?id={vid_id}&done=1",
            method="POST",
            headers={**cookie_hdr, "Content-Type": "application/octet-stream"},
            data=vid_c2,
        )
        assert_eq(st_v2, 200, "video chunk 2 finalize ok")
        vid_url = json.loads(vb2)["url"]
        assert_eq(vid_url, f"/uploads/{vid_id}", "final video url")
        temp_files.append(os.path.join(SITE, "content", vid_url.lstrip("/")))

        # Verify video MIME + full 200 + RFC 9110 Range 206 Partial Content + 416
        st_vf, vh_f, vb_f = http_req(vid_url)
        assert_eq(st_vf, 200, "GET video 200")
        assert_eq(vb_f, vid_all, "full video bytes match")
        assert "video/mp4" in vh_f.get("Content-Type", ""), f"bad video mime: {vh_f}"
        assert vh_f.get("Accept-Ranges") == "bytes"

        st_r1, hr1, br1 = http_req(vid_url, headers={"Range": "bytes=0-15"})
        assert_eq(st_r1, 206, "Range 0-15 -> 206")
        assert_eq(br1, vid_all[:16], "Range 0-15 bytes")
        assert_eq(hr1.get("Content-Range"), f"bytes 0-15/{len(vid_all)}", "Content-Range 0-15")

        st_r2, hr2, br2 = http_req(vid_url, headers={"Range": "bytes=20-"})
        assert_eq(st_r2, 206, "Range 20- -> 206")
        assert_eq(br2, vid_all[20:], "Range 20- bytes")
        assert_eq(hr2.get("Content-Range"), f"bytes 20-{len(vid_all)-1}/{len(vid_all)}", "Content-Range 20-")

        st_r3, hr3, br3 = http_req(vid_url, headers={"Range": "bytes=-10"})
        assert_eq(st_r3, 206, "Range -10 -> 206")
        assert_eq(br3, vid_all[-10:], "Range -10 bytes")
        assert_eq(hr3.get("Content-Range"), f"bytes {len(vid_all)-10}-{len(vid_all)-1}/{len(vid_all)}", "Content-Range -10")

        st_r4, hr4, _ = http_req(vid_url, headers={"Range": "bytes=999999-"})
        assert_eq(st_r4, 416, "Out-of-bounds Range -> 416")
        assert_eq(hr4.get("Content-Range"), f"bytes */{len(vid_all)}", "Content-Range 416")

        # Add custom category
        st_ca, _, _ = http_req(
            "/api/studio/categories",
            method="POST",
            headers={**cookie_hdr, "Content-Type": "application/json"},
            data=json.dumps({"name": "测试相册"}).encode(),
        )
        assert_eq(st_ca, 200, "add category")
        cats = json.loads(http_req("/api/studio/categories", headers=cookie_hdr)[2])
        assert any(c["name"] == "测试相册" for c in cats), f"new category missing: {cats}"

        # Publish post with cover + category + inline uploaded image + inline uploaded video
        post_payload = {
            "title": "测试图文日记",
            "slug": "studio-e2e-demo",
            "date": "2026-11-24",
            "category": "测试相册",
            "tags": "图文, 测试",
            "summary": "一篇带封面图与正文插图的测试文章",
            "cover": up_url,
            "draft": "false",
            "content": f"## 图文测试\n\n这里是一张插图：\n\n![可爱插图]({up_url})\n\n这里是一段视频：\n\n![精彩片段]({vid_url}?poster={up_url})\n",
        }
        st_sp, _, sp_body = http_req(
            "/api/studio/posts",
            method="POST",
            headers={**cookie_hdr, "Content-Type": "application/json"},
            data=json.dumps(post_payload).encode(),
        )
        assert_eq(st_sp, 200, "publish studio post")
        assert_eq(json.loads(sp_body)["slug"], "studio-e2e-demo")

        # Verify public rendering on post detail and category page (including HTML5 <video>)
        st_vp, _, vp_html = http_req("/post/studio-e2e-demo/")
        assert_eq(st_vp, 200, "public view of studio post")
        vp_txt = vp_html.decode("utf-8")
        assert "测试图文日记" in vp_txt and f'src="{up_url}"' in vp_txt and "测试相册" in vp_txt
        assert f'<video class="prose-video" src="{vid_url}?poster={up_url}" title="精彩片段" controls playsinline preload="metadata"></video>' in vp_txt, "HTML5 video tag missing"

        st_vc, _, vc_html = http_req("/category/" + urllib.parse.quote("测试相册") + "/")
        assert_eq(st_vc, 200, "new category page")
        assert "测试图文日记" in vc_html.decode("utf-8")

        # Verify GET single post returns raw markdown content for editing
        st_gp, _, gp_body = http_req("/api/studio/posts/studio-e2e-demo", headers=cookie_hdr)
        assert_eq(st_gp, 200, "studio get post")
        gp_obj = json.loads(gp_body)
        assert_eq(gp_obj["cover"], up_url)
        assert_eq(gp_obj["category"], "测试相册")
        assert f"![可爱插图]({up_url})" in gp_obj["content"]

        # Delete custom category -> disappears from category list AND cleared from post
        st_cd, _, _ = http_req(
            "/api/studio/categories/delete",
            method="POST",
            headers={**cookie_hdr, "Content-Type": "application/json"},
            data=json.dumps({"name": "测试相册"}).encode(),
        )
        assert_eq(st_cd, 200, "delete category")
        cats_after = json.loads(http_req("/api/studio/categories", headers=cookie_hdr)[2])
        assert not any(c["name"] == "测试相册" for c in cats_after), f"deleted category remained: {cats_after}"
        gp_after = json.loads(http_req("/api/studio/posts/studio-e2e-demo", headers=cookie_hdr)[2])
        assert_eq(gp_after["category"], "", "post category should be cleared when category deleted")

        # Delete test post -> 404 on frontend
        st_dp, _, _ = http_req("/api/studio/posts/studio-e2e-demo", method="DELETE", headers=cookie_hdr)
        assert_eq(st_dp, 200, "delete studio post")
        assert_eq(http_req("/post/studio-e2e-demo/")[0], 404, "deleted post must 404")

        # Settings API: read, update appearance + custom studio_path + password hot-reload
        st_sg, _, sg_body = http_req("/api/studio/settings", headers=cookie_hdr)
        assert_eq(st_sg, 200, "GET /api/studio/settings")
        sg_obj = json.loads(sg_body)
        assert_eq(sg_obj["studio_path"], "/studio")

        st_ss, _, ss_body = http_req(
            "/api/studio/settings",
            method="POST",
            headers={**cookie_hdr, "Content-Type": "application/json"},
            data=json.dumps({
                "site_name": "Starlight Anime Blog",
                "footer_text": "Custom Live Footer ♡",
                "studio_path": "/my-secret-room",
                "giscus_repo": "snlyj/asmblog",
                "giscus_repo_id": "R_kgDOTest123",
                "giscus_category": "General",
                "giscus_category_id": "DIC_kwDOTest456",
                "new_password": "new-strong-pass",
            }).encode(),
        )
        assert_eq(st_ss, 200, "POST /api/studio/settings")
        assert_eq(json.loads(ss_body)["studio_path"], "/my-secret-room")

        # Verify instant hot-reload of appearance, Giscus comments & custom studio_path (old /studio -> 404!)
        new_home = http_req("/")[2].decode("utf-8")
        assert "Starlight Anime Blog" in new_home and "Custom Live Footer ♡" in new_home
        new_post = http_req("/post/welcome-to-asmblog/")[2].decode("utf-8")
        assert 'data-repo="snlyj/asmblog"' in new_post and 'data-category-id="DIC_kwDOTest456"' in new_post, "Giscus comments must hot-reload onto article pages"
        sg_after = json.loads(http_req("/api/studio/settings", headers=cookie_hdr)[2])
        assert_eq(sg_after["giscus_repo"], "snlyj/asmblog")
        assert_eq(sg_after["giscus_category_id"], "DIC_kwDOTest456")
        assert_eq(http_req("/studio")[0], 404, "old /studio must 404 after studio_path changed")
        assert_eq(http_req("/my-secret-room")[0], 200, "new custom studio_path must return 200")

        # Logout revokes session server-side (reusing old cookie must immediately return 401)
        st_lo, h_lo, _ = http_req("/api/studio/logout", method="POST", headers=cookie_hdr)
        assert_eq(st_lo, 200, "studio logout")
        assert "Max-Age=0" in h_lo.get("Set-Cookie", ""), "logout must expire cookie"
        assert_eq(http_req("/api/studio/posts", headers=cookie_hdr)[0], 401, "revoked session token must fail")

        # Verify login with updated password works
        st_np, _, _ = http_req(
            "/api/studio/login",
            method="POST",
            headers={"Content-Type": "application/json"},
            data=json.dumps({"password": "new-strong-pass"}).encode(),
        )
        assert_eq(st_np, 200, "login with updated password")

        # Brute-force protection: 5 wrong logins trigger 429 Too Many Requests + Retry-After: 60
        for i in range(4):
            st_bf, _, _ = http_req(
                "/api/studio/login",
                method="POST",
                headers={"Content-Type": "application/json"},
                data=json.dumps({"password": f"bad-{i}"}).encode(),
            )
            assert_eq(st_bf, 401, f"wrong attempt {i+1}")
        st_lock, h_lock, _ = http_req(
            "/api/studio/login",
            method="POST",
            headers={"Content-Type": "application/json"},
            data=json.dumps({"password": "bad-5"}).encode(),
        )
        assert_eq(st_lock, 429, "5th wrong attempt must return 429 lockout")
        assert_eq(h_lock.get("Retry-After"), "60", "Retry-After header")
        st_during, _, _ = http_req(
            "/api/studio/login",
            method="POST",
            headers={"Content-Type": "application/json"},
            data=json.dumps({"password": "new-strong-pass"}).encode(),
        )
        assert_eq(st_during, 429, "correct password must stay blocked during 60s lockout")

        if os.path.exists(uploaded_disk_path):
            os.unlink(uploaded_disk_path)
            temp_files.remove(uploaded_disk_path)
        print("[PASS] Hidden Author Studio (random session tokens, 429 brute-force lock, custom path, live settings, CRUD)")

        # 9. Concurrency & Memory/FD Leak Benchmark (20 threads x 100 req = 2000 reqs)
        rss_before = read_rss_kb(proc.pid)
        fd_before = count_fds(proc.pid)
        bench_paths = ["/", "/post/welcome-to-asmblog/", "/static/sky-ribbon.css", "/search-index.json"]

        def worker(tid):
            ok = 0
            for j in range(100):
                st, _, _ = http_req(bench_paths[(tid + j) % len(bench_paths)])
                if st == 200:
                    ok += 1
            return ok

        t0 = time.monotonic()
        with concurrent.futures.ThreadPoolExecutor(max_workers=20) as ex:
            total_ok = sum(ex.map(worker, range(20)))
        dt = time.monotonic() - t0
        time.sleep(0.15)
        rss_after = read_rss_kb(proc.pid)
        fd_after = count_fds(proc.pid)

        assert_eq(total_ok, 2000, "all 2000 concurrent requests must return 200")
        assert fd_after <= fd_before + 2, f"FD leak detected: before={fd_before}, after={fd_after}"
        qps = total_ok / dt
        print(
            f"[PASS] Concurrency benchmark: {total_ok}/2000 OK in {dt:.3f}s ({qps:.0f} req/s), "
            f"VmRSS {rss_before} KiB -> {rss_after} KiB, FDs {fd_before} -> {fd_after}"
        )

        # 10. Graceful SIGTERM shutdown
        proc.send_signal(signal.SIGTERM)
        rc = proc.wait(timeout=5)
        assert_eq(rc, 0, "graceful SIGTERM exit code")
        print("[PASS] Graceful SIGTERM shutdown (exit code 0)")
    finally:
        for p in temp_files:
            if os.path.exists(p):
                os.unlink(p)
        if proc.poll() is None:
            proc.kill()
            proc.wait()


if __name__ == "__main__":
    test_elf()
    test_cli_init_new_build()
    test_site_ssg_build()
    test_server()
    print("\nALL TESTS PASSED!")
