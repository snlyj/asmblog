#!/usr/bin/env python3
import concurrent.futures
import hashlib
import io
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tarfile
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

        # Valid XML for RSS and Sitemap + SSG gallery/about/moments/bgm outputs
        rss = ET.fromstring(open(os.path.join(dist_tmp, "rss.xml"), encoding="utf-8").read())
        assert len(rss.findall(".//item")) == 3
        sm = ET.fromstring(open(os.path.join(dist_tmp, "sitemap.xml"), encoding="utf-8").read())
        assert len(list(sm)) == 7  # home + gallery + about + moments + 3 posts
        assert "精选画廊" in open(os.path.join(dist_tmp, "gallery/index.html"), encoding="utf-8").read()
        assert "friends-grid" in open(os.path.join(dist_tmp, "about/index.html"), encoding="utf-8").read()
        assert "moments-feed" in open(os.path.join(dist_tmp, "moments/index.html"), encoding="utf-8").read()
        assert isinstance(json.loads(open(os.path.join(dist_tmp, "gallery.json"), encoding="utf-8").read()), list)
        assert isinstance(json.loads(open(os.path.join(dist_tmp, "about.json"), encoding="utf-8").read()), dict)
        assert isinstance(json.loads(open(os.path.join(dist_tmp, "bgm.json"), encoding="utf-8").read()), list)
        assert isinstance(json.loads(open(os.path.join(dist_tmp, "moments.json"), encoding="utf-8").read()), list)

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

    # Pre-seed content/stats.txt with CRLF, blank & malformed lines to test restart persistence parser!
    stats_seed_path = os.path.join(SITE, "content/stats.txt")
    with open(stats_seed_path, "wb") as sf:
        sf.write(b"\r\nwelcome-to-asmblog 7 3\r\n../bad-slug 9 9\nx86-64-assembly-architecture 4 1\n")

    proc = subprocess.Popen(
        [BIN, "serve", "-d", SITE, "-c", tmp_cfg_path, "-p", str(PORT)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    temp_files = [tmp_cfg_path, tmp_cfg_path + ".tmp", stats_seed_path]
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
            "/gallery",
            "/gallery/",
            "/about",
            "/about/",
            "/moments",
            "/moments/",
            "/gallery.json",
            "/about.json",
            "/bgm.json",
            "/moments.json",
            "/api/stats",
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

        st_imm, hdrs_imm, css_v18 = http_req("/static/sky-ribbon.css?v=18")
        assert_eq(st_imm, 200, "versioned static css 200")
        assert "immutable" in hdrs_imm.get("Cache-Control", ""), f"expected immutable on versioned URL: {hdrs_imm}"
        css_rules = re.sub(rb"/\*[\s\S]*?\*/", b"", css_v18)
        for forbidden in (b"100dvh", b"backdrop-filter", b"filter: blur", b"position: sticky"):
            assert forbidden not in css_rules, f"forbidden jank CSS rule found: {forbidden!r}"
        for required_css in (b"hover: hover", b".lightbox", b".lightbox-badge", b".prose-video", b".pjax-loader", b".post-grid", b".pin-badge", b".gallery-masonry", b".about-hero-card", b".friends-grid", b".bgm-dock", b"visibility: hidden", b".draft-preview-banner", b".like-btn", b".moments-feed", b".moment-card", b".toc-desktop", b".toc-mobile", b".toc-sheet", b".article-fabs", b".cmd-modal", b".font-size-ctrl", b".sky-toast", b".search-hl", b".archive-year", b".comments-card"):
            assert required_css in css_rules, f"missing expected UI CSS rule: {required_css!r}"

        st_js, _, js_v18 = http_req("/static/sky-ribbon.js?v=18")
        assert_eq(st_js, 200, "versioned static js 200")
        for required_js in (b"img-lightbox", b"extractOrigUrl", b"loadedOrigs", b"zoomLightboxAt", b"preloadAdjacent", b"enhanceVideos", b"initGallery", b"initAbout", b"initMoments", b"initArticleStats", b"formatMomentText", b"initBgmPlayer", b"pauseBgm", b"ring-progress", b"pjax-loader", b"initArticleExtras", b"initArchiveYears", b"initComments", b"syncGiscusTheme", b"setLightboxZoom", b"showToast", b"highlightText", b"openCmdSearch", b"openTocSheet", b"applyFontSize", b"scrollMemo", b"touchstart"):
            assert required_js in js_v18, f"missing expected UI JS feature: {required_js!r}"

        _, _, sm_xml = http_req("/sitemap.xml")
        sm_txt = sm_xml.decode("utf-8")
        assert "/gallery/</loc>" in sm_txt and "/about/</loc>" in sm_txt and "/moments/</loc>" in sm_txt, "sitemap must include /gallery/, /about/ and /moments/"

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
        for required_st in ("draft-restore-bar", "upload-progress-wrap", "posts-filter-bar", "posts-stats-badge", "posts-sort", "studio-theme-btn", "word-count-badge", "data-toggle-draft", "f-pinned", "tab-moments", "mom-compose-box", "tab-gallery", "tab-media", "tab-about", "tab-bgm", "media-clean-btn", "backup-download-btn"):
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
            ("POST", "/api/studio/upload-audio"),
            ("POST", "/api/studio/gallery"),
            ("POST", "/api/studio/about"),
            ("POST", "/api/studio/bgm"),
            ("POST", "/api/studio/moments"),
            ("GET", "/api/studio/media"),
            ("POST", "/api/studio/media/delete"),
            ("GET", "/api/studio/backup"),
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

        # Verify large 2 MiB upload releases physical RX pages back to kernel via madvise(MADV_DONTNEED)
        rss_pre_big = read_rss_kb(proc.pid)
        big_png = tiny_png + (b"\x00" * (2 * 1024 * 1024))
        st_big, _, big_body = http_req(
            "/api/studio/upload",
            method="POST",
            headers={**cookie_hdr, "Content-Type": "image/png"},
            data=big_png,
        )
        assert_eq(st_big, 201, "2 MiB upload 201")
        big_url = json.loads(big_body)["url"]
        big_disk = os.path.join(SITE, "content", big_url.lstrip("/"))
        temp_files.append(big_disk)
        time.sleep(0.05)
        rss_post_big = read_rss_kb(proc.pid)
        assert rss_post_big <= rss_pre_big + 512, f"RX pages not reclaimed after 2 MiB upload: before={rss_pre_big}KiB, after={rss_post_big}KiB"
        os.unlink(big_disk)
        temp_files.remove(big_disk)

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

        # Publish PINNED post with older date (must float ABOVE newer 2026 posts!) + cover + inline image + video
        post_payload = {
            "title": "测试图文日记",
            "slug": "studio-e2e-demo",
            "date": "2020-01-01",
            "category": "测试相册",
            "tags": "图文, 测试",
            "summary": "一篇带封面图与正文插图的测试文章",
            "cover": up_url,
            "draft": "false",
            "pinned": "true",
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

        # Verify pinned post floats FIRST on homepage ahead of newer 2026 posts & renders pin-badge
        pin_home = http_req("/")[2].decode("utf-8")
        assert "pin-badge" in pin_home and "📌 置顶" in pin_home, "pin-badge missing on homepage"
        assert pin_home.index("测试图文日记") < pin_home.index("欢迎使用 AsmBlog"), "pinned 2020 post must sort ahead of newer posts"

        # Verify public rendering on post detail and category page (including HTML5 <video>)
        st_vp, _, vp_html = http_req("/post/studio-e2e-demo/")
        assert_eq(st_vp, 200, "public view of studio post")
        vp_txt = vp_html.decode("utf-8")
        assert "测试图文日记" in vp_txt and f'src="{up_url}"' in vp_txt and "测试相册" in vp_txt and "pin-badge" in vp_txt
        assert f'<video class="prose-video" src="{vid_url}?poster={up_url}" title="精彩片段" controls playsinline preload="metadata"></video>' in vp_txt, "HTML5 video tag missing"

        st_vc, _, vc_html = http_req("/category/" + urllib.parse.quote("测试相册") + "/")
        assert_eq(st_vc, 200, "new category page")
        assert "测试图文日记" in vc_html.decode("utf-8")

        # Verify GET single post returns raw markdown content & pinned=True for editing
        st_gp, _, gp_body = http_req("/api/studio/posts/studio-e2e-demo", headers=cookie_hdr)
        assert_eq(st_gp, 200, "studio get post")
        gp_obj = json.loads(gp_body)
        assert_eq(gp_obj["cover"], up_url)
        assert_eq(gp_obj["category"], "测试相册")
        assert_eq(gp_obj["pinned"], True, "pinned flag round-trip")
        assert f"![可爱插图]({up_url})" in gp_obj["content"]

        # Curated Gallery, About/Friends, Moments, Audio BGM, Views/Likes, Draft Preview, Media Library & .tar Backup E2E
        gal_path = os.path.join(SITE, "content/gallery.json")
        abt_path = os.path.join(SITE, "content/about.json")
        bgm_path = os.path.join(SITE, "content/bgm.json")
        mom_path = os.path.join(SITE, "content/moments.json")
        stats_path = stats_seed_path
        temp_files.extend([gal_path, abt_path, bgm_path, mom_path])

        # 1) Curated Gallery save & public read (+ reject truncated/mismatched JSON)
        for ep, bad_j in [
            ("/api/studio/gallery", b'[{"id":"truncated"'),
            ("/api/studio/about", b'{"bio":"mismatched"]'),
            ("/api/studio/bgm", b'[{}'),
            ("/api/studio/moments", b'[{"id":"bad"'),
        ]:
            st_tj, _, _ = http_req(ep, method="POST", headers={**cookie_hdr, "Content-Type": "application/json"}, data=bad_j)
            assert_eq(st_tj, 400, f"{ep} must reject truncated/mismatched JSON")

        gal_data = [{"id": "g1", "url": up_url, "title": "晴空美少女", "tag": "原画", "note": "精选测试", "date": "2026-11-26"}]
        st_gs, _, _ = http_req("/api/studio/gallery", method="POST", headers={**cookie_hdr, "Content-Type": "application/json"}, data=json.dumps(gal_data).encode())
        assert_eq(st_gs, 200, "POST /api/studio/gallery")
        assert_eq(json.loads(http_req("/gallery.json")[2])[0]["title"], "晴空美少女", "GET /gallery.json")
        assert "精选画廊" in http_req("/gallery/")[2].decode("utf-8")

        # 2) About & Friends save & public read
        abt_data = {"bio": "你好晴空\n第二行简介", "tags": ["二次元", "插画"], "socials": [{"label": "GitHub", "url": "https://github.com/snlyj"}], "friends": [{"name": "晴空友链", "url": "https://example.com", "avatar": up_url, "desc": "好朋友"}]}
        st_as, _, _ = http_req("/api/studio/about", method="POST", headers={**cookie_hdr, "Content-Type": "application/json"}, data=json.dumps(abt_data).encode())
        assert_eq(st_as, 200, "POST /api/studio/about")
        assert_eq(json.loads(http_req("/about.json")[2])["friends"][0]["name"], "晴空友链", "GET /about.json")
        assert "friends-grid" in http_req("/about/")[2].decode("utf-8")

        # 3) Audio MP3 upload + audio/mpeg MIME + Range 206 + BGM playlist save
        fake_mp3 = b"ID3\x03\x00\x00\x00\x00\x00\x00" + (b"\xff\xfb\x90\x00" * 16)
        st_au, _, au_body = http_req("/api/studio/upload-audio?done=1", method="POST", headers={**cookie_hdr, "Content-Type": "application/octet-stream"}, data=fake_mp3)
        assert_eq(st_au, 200, "upload MP3 audio 200")
        aud_url = json.loads(au_body)["url"]
        assert aud_url.endswith(".mp3"), f"expected .mp3 url, got {aud_url}"
        aud_disk = os.path.join(SITE, "content", aud_url.lstrip("/"))
        temp_files.append(aud_disk)
        st_am, ah_m, ab_m = http_req(aud_url, headers={"Range": "bytes=0-9"})
        assert_eq(st_am, 206, "audio Range 206")
        assert "audio/mpeg" in ah_m.get("Content-Type", ""), f"bad audio mime: {ah_m}"
        assert_eq(ab_m, fake_mp3[:10], "audio range bytes")

        bgm_data = [{"title": "晴空微风", "artist": "Sakura", "url": aud_url}]
        st_bs, _, _ = http_req("/api/studio/bgm", method="POST", headers={**cookie_hdr, "Content-Type": "application/json"}, data=json.dumps(bgm_data).encode())
        assert_eq(st_bs, 200, "POST /api/studio/bgm")
        assert_eq(json.loads(http_req("/bgm.json")[2])[0]["title"], "晴空微风", "GET /bgm.json")

        # 3b) Moments / 碎碎念 save, public read & image reference protection
        st_mu, _, mu_body = http_req("/api/studio/upload", method="POST", headers={**cookie_hdr, "Content-Type": "image/png"}, data=tiny_png)
        assert_eq(st_mu, 201, "upload moment PNG")
        mom_img_url = json.loads(mu_body)["url"]
        mom_img_name = mom_img_url.rsplit("/", 1)[-1]
        mom_img_disk = os.path.join(SITE, "content/uploads", mom_img_name)
        temp_files.append(mom_img_disk)
        mom_data = [{"id": "m1", "text": "今天晴空超美 https://example.com ✨", "images": [mom_img_url], "mood": "✨ 日常", "date": "2026-11-27 10:00", "pinned": True}]
        st_ms, _, _ = http_req("/api/studio/moments", method="POST", headers={**cookie_hdr, "Content-Type": "application/json"}, data=json.dumps(mom_data).encode())
        assert_eq(st_ms, 200, "POST /api/studio/moments")
        assert_eq(json.loads(http_req("/moments.json")[2])[0]["mood"], "✨ 日常", "GET /moments.json")
        assert "moments-feed" in http_req("/moments/")[2].decode("utf-8")

        # 3c) Zero-Tracker Post Views & Heart Likes API (including disk reload from pre-seeded stats.txt + 429 rate-limit!)
        st_s0, _, bs0 = http_req("/api/stats/welcome-to-asmblog")
        assert_eq(st_s0, 200, "GET pre-seeded stats")
        assert_eq(json.loads(bs0), {"slug": "welcome-to-asmblog", "views": 7, "likes": 3}, "must load persisted stats.txt cleanly")
        st_v, hv, bv = http_req("/api/stats/view", method="POST", headers={"Content-Type": "application/json"}, data=json.dumps({"slug": "welcome-to-asmblog"}).encode())
        assert_eq(st_v, 200, "POST /api/stats/view")
        assert "no-store" in hv.get("Cache-Control", "")
        assert_eq(json.loads(bv), {"slug": "welcome-to-asmblog", "views": 8, "likes": 3}, "view count=8")
        st_l, _, bl = http_req("/api/stats/like", method="POST", headers={"Content-Type": "application/json"}, data=json.dumps({"slug": "welcome-to-asmblog"}).encode())
        assert_eq(st_l, 200, "POST /api/stats/like")
        assert_eq(json.loads(bl), {"slug": "welcome-to-asmblog", "views": 8, "likes": 4}, "like count=4")
        st_s1, _, bs1 = http_req("/api/stats/welcome-to-asmblog")
        assert_eq(st_s1, 200, "GET /api/stats/:slug")
        assert_eq(json.loads(bs1), {"slug": "welcome-to-asmblog", "views": 8, "likes": 4}, "GET stats must not increment")
        st_sa, _, bsa = http_req("/api/stats")
        assert_eq(st_sa, 200, "GET /api/stats")
        sa_obj = json.loads(bsa)
        assert_eq(sa_obj["total_views"], 12, "total_views (8 + 4, bad line skipped)")
        assert_eq(sa_obj["total_likes"], 5, "total_likes (4 + 1, bad line skipped)")
        assert_eq(http_req("/api/stats/view", method="POST", headers={"Content-Type": "application/json"}, data=json.dumps({"slug": "no-such-slug"}).encode())[0], 404, "nonexistent slug view -> 404")
        assert_eq(http_req("/api/stats/view", method="POST", headers={"Content-Type": "application/json"}, data=json.dumps({"slug": "../evil"}).encode())[0], 400, "unsafe slug view -> 400")
        assert os.path.isfile(stats_path) and "welcome-to-asmblog 8 4" in open(stats_path, encoding="utf-8").read()

        # 3d) Author Draft Live Preview (404 for guests, 200 no-store with banner for logged-in author!)
        draft_payload = {
            "title": "私密草稿预览测试",
            "slug": "studio-draft-preview",
            "date": "2026-11-27",
            "summary": "草稿摘要",
            "draft": "true",
            "content": "这是一篇未公开的草稿正文。",
        }
        assert_eq(http_req("/api/studio/posts", method="POST", headers={**cookie_hdr, "Content-Type": "application/json"}, data=json.dumps(draft_payload).encode())[0], 200, "save draft post")
        assert_eq(http_req("/post/studio-draft-preview/")[0], 404, "guest must get 404 on draft post")
        assert_eq(http_req("/api/stats/view", method="POST", headers={"Content-Type": "application/json"}, data=json.dumps({"slug": "studio-draft-preview"}).encode())[0], 404, "stats view on draft must 404")
        st_dpv, h_dpv, b_dpv = http_req("/post/studio-draft-preview/", headers=cookie_hdr)
        assert_eq(st_dpv, 200, "logged-in author must preview draft post")
        assert "no-store" in h_dpv.get("Cache-Control", "") and "ETag" not in h_dpv, f"draft preview must be strictly no-store: {h_dpv}"
        dpv_txt = b_dpv.decode("utf-8")
        assert "draft-preview-banner" in dpv_txt and "私密草稿预览测试" in dpv_txt and "未公开的草稿正文" in dpv_txt
        assert_eq(http_req("/api/studio/posts/studio-draft-preview", method="DELETE", headers=cookie_hdr)[0], 200, "delete draft preview post")

        # 4) Media Library reference scan & safe orphan/unused delete
        st_uu, _, uu_body = http_req("/api/studio/upload", method="POST", headers={**cookie_hdr, "Content-Type": "image/png"}, data=tiny_png)
        assert_eq(st_uu, 201, "upload unreferenced PNG")
        unused_name = json.loads(uu_body)["url"].rsplit("/", 1)[-1]
        orphan_part_name = ".orphan-test.mp4.part"
        orphan_part_disk = os.path.join(SITE, "content/uploads", orphan_part_name)
        with open(orphan_part_disk, "wb") as pf:
            pf.write(b"partial")
        temp_files.extend([os.path.join(SITE, "content/uploads", unused_name), orphan_part_disk])

        st_ml, _, ml_body = http_req("/api/studio/media", headers=cookie_hdr)
        assert_eq(st_ml, 200, "GET /api/studio/media")
        media_by_name = {m["name"]: m for m in json.loads(ml_body)}
        up_name = up_url.rsplit("/", 1)[-1]
        aud_name = aud_url.rsplit("/", 1)[-1]
        assert media_by_name[up_name]["used"] is True and media_by_name[up_name]["part"] is False
        assert media_by_name[aud_name]["used"] is True and media_by_name[aud_name]["part"] is False
        assert media_by_name[mom_img_name]["used"] is True and media_by_name[mom_img_name]["part"] is False, "moment photo must be protected as used!"
        assert media_by_name[unused_name]["used"] is False and media_by_name[unused_name]["part"] is False
        assert media_by_name[orphan_part_name]["used"] is False and media_by_name[orphan_part_name]["part"] is True

        # 5) One-Click Full Site Backup (.tar POSIX ustar streaming via sendfile)
        st_bk, h_bk, bk_bytes = http_req("/api/studio/backup", headers=cookie_hdr)
        assert_eq(st_bk, 200, "GET /api/studio/backup")
        assert "application/x-tar" in h_bk.get("Content-Type", ""), f"bad backup mime: {h_bk}"
        assert "no-store" in h_bk.get("Cache-Control", "")
        assert ".tar" in h_bk.get("Content-Disposition", "")
        assert not os.path.exists(os.path.join(SITE, "content/.backup.tar.tmp")), "unlinked backup temp file must not remain on disk"
        with tarfile.open(fileobj=io.BytesIO(bk_bytes), mode="r:") as tf:
            names = set(tf.getnames())
            for req_arc in (
                "asmblog-backup/config.ini",
                "asmblog-backup/content/posts/welcome-to-asmblog.md",
                "asmblog-backup/content/gallery.json",
                "asmblog-backup/content/about.json",
                "asmblog-backup/content/bgm.json",
                "asmblog-backup/content/moments.json",
                "asmblog-backup/content/stats.txt",
                f"asmblog-backup/content/uploads/{up_name}",
                f"asmblog-backup/content/uploads/{mom_img_name}",
            ):
                assert req_arc in names, f"missing expected backup member {req_arc} in {sorted(names)}"
            assert all("/." not in n for n in names), f"hidden dotfile leaked into backup tar: {names}"
            assert_eq(tf.extractfile(f"asmblog-backup/content/uploads/{up_name}").read(), tiny_png, "backup PNG bytes exact match")
            assert "welcome-to-asmblog 8 4" in tf.extractfile("asmblog-backup/content/stats.txt").read().decode("utf-8")

        # Verify 60s sliding-window like anti-spam limiter triggers 429 + Retry-After: 60 after 30 likes
        for _ in range(29):
            st_lk, _, _ = http_req("/api/stats/like", method="POST", headers={"Content-Type": "application/json"}, data=json.dumps({"slug": "welcome-to-asmblog"}).encode())
            assert_eq(st_lk, 200, "like within 30/60s quota")
        st_lk429, h_lk429, _ = http_req("/api/stats/like", method="POST", headers={"Content-Type": "application/json"}, data=json.dumps({"slug": "welcome-to-asmblog"}).encode())
        assert_eq(st_lk429, 429, "31st like in 60s must return 429")
        assert_eq(h_lk429.get("Retry-After"), "60", "like 429 Retry-After")

        # Reject protected/unsafe delete names; allow deleting unused & orphan .part
        for bad_n in (".gitkeep", "../config.ini", "a/b.png", "."):
            st_bd, _, _ = http_req("/api/studio/media/delete", method="POST", headers={**cookie_hdr, "Content-Type": "application/json"}, data=json.dumps({"name": bad_n}).encode())
            assert_eq(st_bd, 400, f"media delete must reject {bad_n!r}")
        for ok_n in (unused_name, orphan_part_name):
            st_od, _, _ = http_req("/api/studio/media/delete", method="POST", headers={**cookie_hdr, "Content-Type": "application/json"}, data=json.dumps({"name": ok_n}).encode())
            assert_eq(st_od, 200, f"media delete {ok_n}")
        assert not os.path.exists(orphan_part_disk)
        for p_clean in (gal_path, abt_path, bgm_path, mom_path, stats_path, aud_disk, mom_img_disk):
            if os.path.exists(p_clean):
                os.unlink(p_clean)
                temp_files.remove(p_clean)
        temp_files.remove(orphan_part_disk)
        temp_files.remove(os.path.join(SITE, "content/uploads", unused_name))

        # Delete custom category -> disappears from category list AND cleared from post (preserving pinned!)
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
        assert_eq(gp_after["pinned"], True, "post pinned flag must survive category deletion")

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
