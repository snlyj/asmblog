(function () {
  var root = document.documentElement;
  var stage = document.getElementById('pjax-stage');
  var loader = document.getElementById('pjax-loader');
  var progressFill = document.getElementById('progress-fill');
  var ringProgress = document.getElementById('ring-progress');
  var nav = document.getElementById('primary-nav');
  var navSlider = document.getElementById('nav-slider');
  var themeBtn = document.getElementById('theme-toggle');
  var fxBtn = document.getElementById('fx-toggle');
  var backTop = document.getElementById('back-top');

  var reducedMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var RING_CIRC = 119.38;
  var prefetchCache = new Map();
  var searchIndexCache = null;
  var isNavigating = false;
  var loaderTimer = null;

  /* ---------------------------------------------------------
     1. Zero-Reflow GPU Scroll Progress + SVG Ring (Single RAF)
     --------------------------------------------------------- */
  var maxScroll = 1;
  var scrollTicking = false;
  var backTopShown = false;

  function recalcMetrics() {
    maxScroll = Math.max(1, root.scrollHeight - window.innerHeight);
    paintScroll();
  }

  function paintScroll() {
    scrollTicking = false;
    var y = window.scrollY || root.scrollTop || 0;
    var ratio = Math.min(1, Math.max(0, y / maxScroll));
    if (progressFill) {
      progressFill.style.transform = 'scaleX(' + ratio.toFixed(4) + ')';
    }
    if (ringProgress) {
      ringProgress.style.strokeDashoffset = (RING_CIRC * (1 - ratio)).toFixed(2);
    }
    if (backTop) {
      var shouldShow = y > 340;
      if (shouldShow !== backTopShown) {
        backTopShown = shouldShow;
        backTop.classList.toggle('is-shown', shouldShow);
      }
    }
  }

  function onScroll() {
    if (!scrollTicking) {
      scrollTicking = true;
      requestAnimationFrame(paintScroll);
    }
  }

  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('resize', function () {
    recalcMetrics();
    updateNavState();
  }, { passive: true });
  window.addEventListener('load', recalcMetrics, { passive: true });

  if (backTop) {
    backTop.addEventListener('click', function () {
      window.scrollTo({ top: 0, behavior: reducedMotion ? 'auto' : 'smooth' });
    });
  }

  /* ---------------------------------------------------------
     2. Dedicated Top PJAX Shimmer Loader (GPU scaleX + opacity)
     --------------------------------------------------------- */
  function startLoader() {
    if (!loader) return;
    clearTimeout(loaderTimer);
    loader.classList.remove('is-done', 'is-loading');
    loader.style.transform = 'scaleX(0)';
    void loader.offsetWidth;
    loader.classList.add('is-loading');
    loader.style.transform = 'scaleX(0.74)';
  }

  function finishLoader() {
    if (!loader) return;
    clearTimeout(loaderTimer);
    loader.classList.remove('is-loading');
    loader.classList.add('is-done');
    loader.style.transform = 'scaleX(1)';
    loaderTimer = setTimeout(function () {
      loader.classList.remove('is-done');
      loader.style.transform = 'scaleX(0)';
    }, 380);
  }

  /* ---------------------------------------------------------
     3. Desktop Sliding Pill + Mobile Grid Active State
     --------------------------------------------------------- */
  function matchNavKey(pathname) {
    var p = pathname || window.location.pathname;
    if (p.indexOf('/archive') === 0) return '/archive';
    if (p.indexOf('/tags') === 0 || p.indexOf('/tag/') === 0) return '/tags';
    if (p.indexOf('/search') === 0) return '/search';
    return '/';
  }

  function moveSliderTo(el) {
    if (!nav || !navSlider || !el) return;
    if (window.getComputedStyle(navSlider).display === 'none') return;
    var navRect = nav.getBoundingClientRect();
    var rect = el.getBoundingClientRect();
    if (!rect.width) return;
    navSlider.style.width = rect.width + 'px';
    navSlider.style.transform = 'translateX(' + (rect.left - navRect.left) + 'px)';
    navSlider.style.opacity = '1';
  }

  function updateNavState(pathname) {
    if (!nav) return;
    var key = matchNavKey(pathname);
    var active = null;
    nav.querySelectorAll('a[data-nav]').forEach(function (a) {
      var on = a.getAttribute('data-nav') === key;
      a.classList.toggle('is-active', on);
      if (on) active = a;
    });
    if (active) moveSliderTo(active);
  }

  if (nav) {
    nav.addEventListener('mouseover', function (e) {
      var a = e.target.closest('a[data-nav]');
      if (a) moveSliderTo(a);
    });
    nav.addEventListener('mouseleave', function () {
      updateNavState();
    });
  }

  /* ---------------------------------------------------------
     4. Silky Circular-Ripple Day/Night Theme Toggle
     --------------------------------------------------------- */
  function store(key, val) {
    try { localStorage.setItem(key, val); } catch (_) { /* storage disabled: keep in-memory state only */ }
  }

  function applyTheme(next) {
    root.setAttribute('data-theme', next);
    store('asmblog-theme', next);
  }

  if (themeBtn) {
    themeBtn.addEventListener('click', function (e) {
      var cur = root.getAttribute('data-theme') === 'dark' ? 'dark' : 'light';
      var next = cur === 'dark' ? 'light' : 'dark';

      if (!document.startViewTransition || reducedMotion) {
        applyTheme(next);
        return;
      }

      var rect = themeBtn.getBoundingClientRect();
      var x = e.clientX || (rect.left + rect.width / 2);
      var y = e.clientY || (rect.top + rect.height / 2);
      var maxR = Math.hypot(
        Math.max(x, window.innerWidth - x),
        Math.max(y, window.innerHeight - y)
      );

      root.classList.add('theme-ripple');
      var vt = document.startViewTransition(function () {
        applyTheme(next);
      });
      vt.ready.then(function () {
        document.documentElement.animate(
          {
            clipPath: [
              'circle(0px at ' + x + 'px ' + y + 'px)',
              'circle(' + maxR + 'px at ' + x + 'px ' + y + 'px)'
            ]
          },
          {
            duration: 460,
            easing: 'cubic-bezier(0.22, 1, 0.36, 1)',
            pseudoElement: '::view-transition-new(root)'
          }
        );
      }).catch(function () {});
      vt.finished.finally(function () {
        root.classList.remove('theme-ripple');
      });
    });
  }

  if (fxBtn) {
    fxBtn.addEventListener('click', function () {
      var off = root.getAttribute('data-fx') === 'off';
      if (off) {
        root.removeAttribute('data-fx');
        store('asmblog-fx', 'on');
      } else {
        root.setAttribute('data-fx', 'off');
        store('asmblog-fx', 'off');
      }
    });
  }

  /* ---------------------------------------------------------
     5. Lightweight Pastel Star Click Sparkles + Avatar Boing
     --------------------------------------------------------- */
  var sparkColors = ['#5cb8ff', '#ff94c2', '#ffd86b', '#b9a4ff'];
  var sparkGlyphs = ['✦', '✧', '★', '✦'];

  document.addEventListener('pointerdown', function (e) {
    if (reducedMotion || root.getAttribute('data-fx') === 'off') return;
    if (e.button !== 0) return;
    if (e.target && e.target.closest && e.target.closest('#img-lightbox')) return;
    var count = 5;
    for (var i = 0; i < count; i++) {
      var sp = document.createElement('span');
      sp.className = 'click-spark';
      sp.textContent = sparkGlyphs[i % sparkGlyphs.length];
      sp.style.left = e.clientX + 'px';
      sp.style.top = e.clientY + 'px';
      sp.style.color = sparkColors[(i + Math.floor(Math.random() * 4)) % sparkColors.length];
      var angle = (Math.PI * 2 * i) / count + (Math.random() - 0.5) * 0.45;
      var dist = 20 + Math.random() * 20;
      sp.style.setProperty('--tx', (Math.cos(angle) * dist).toFixed(1) + 'px');
      sp.style.setProperty('--ty', (Math.sin(angle) * dist - 6).toFixed(1) + 'px');
      sp.style.setProperty('--rot', ((Math.random() - 0.5) * 120).toFixed(0) + 'deg');
      document.body.appendChild(sp);
      setTimeout(function (node) {
        if (node && node.parentNode) node.parentNode.removeChild(node);
      }, 680, sp);
    }
  });

  function bindAvatarBoing() {
    var ring = document.querySelector('.avatar-ring');
    if (!ring || ring.dataset.boingBound) return;
    ring.dataset.boingBound = '1';
    ring.addEventListener('click', function () {
      if (reducedMotion) return;
      ring.classList.remove('is-boing');
      void ring.offsetWidth;
      ring.classList.add('is-boing');
      if (root.getAttribute('data-fx') === 'off') return;
      var pops = ['♡', '✦'];
      pops.forEach(function (ch, idx) {
        var el = document.createElement('span');
        el.className = 'avatar-pop';
        el.textContent = ch;
        el.style.setProperty('--px', (idx === 0 ? -16 : 16) + 'px');
        el.style.color = idx === 0 ? '#ff94c2' : '#5cb8ff';
        ring.appendChild(el);
        setTimeout(function () { if (el.parentNode) el.parentNode.removeChild(el); }, 740);
      });
    });
  }

  /* ---------------------------------------------------------
     6. Zero-Blur GPU Illustration Lightbox (Touch Swipe + Keys)
     --------------------------------------------------------- */
  var lb = { el: null, img: null, cap: null, orig: null, prev: null, next: null, items: [], idx: 0, touchX: 0 };

  function ensureLightbox() {
    if (lb.el) return;
    var wrap = document.createElement('div');
    wrap.id = 'img-lightbox';
    wrap.className = 'lightbox';
    wrap.setAttribute('role', 'dialog');
    wrap.setAttribute('aria-modal', 'true');
    wrap.setAttribute('aria-label', '图片预览');
    wrap.innerHTML =
      '<button class="lightbox-close" type="button" aria-label="关闭">✕</button>' +
      '<button class="lightbox-nav lightbox-prev" type="button" aria-label="上一张">‹</button>' +
      '<img class="lightbox-img" alt="">' +
      '<button class="lightbox-nav lightbox-next" type="button" aria-label="下一张">›</button>' +
      '<div class="lightbox-bar"><span class="lightbox-cap"></span><a class="lightbox-orig" target="_blank" rel="noopener">原图 ↗</a></div>';
    document.body.appendChild(wrap);

    lb.el = wrap;
    lb.img = wrap.querySelector('.lightbox-img');
    lb.cap = wrap.querySelector('.lightbox-cap');
    lb.orig = wrap.querySelector('.lightbox-orig');
    lb.prev = wrap.querySelector('.lightbox-prev');
    lb.next = wrap.querySelector('.lightbox-next');

    wrap.querySelector('.lightbox-close').addEventListener('click', closeLightbox);
    lb.prev.addEventListener('click', function (e) { e.stopPropagation(); stepLightbox(-1); });
    lb.next.addEventListener('click', function (e) { e.stopPropagation(); stepLightbox(1); });
    wrap.addEventListener('click', function (e) {
      if (e.target === wrap) closeLightbox();
    });
    wrap.addEventListener('touchstart', function (e) {
      if (e.touches && e.touches.length === 1) lb.touchX = e.touches[0].clientX;
    }, { passive: true });
    wrap.addEventListener('touchend', function (e) {
      if (!lb.touchX || !e.changedTouches || !e.changedTouches.length) return;
      var dx = e.changedTouches[0].clientX - lb.touchX;
      lb.touchX = 0;
      if (Math.abs(dx) > 48 && lb.items.length > 1) stepLightbox(dx < 0 ? 1 : -1);
    }, { passive: true });
  }

  function showLightboxIndex(i) {
    if (!lb.items.length) return;
    lb.idx = (i + lb.items.length) % lb.items.length;
    var item = lb.items[lb.idx];
    lb.img.src = item.src;
    lb.img.alt = item.alt || '';
    lb.orig.href = item.src;
    var countTxt = lb.items.length > 1 ? ('(' + (lb.idx + 1) + ' / ' + lb.items.length + ') ') : '';
    lb.cap.textContent = countTxt + (item.alt || '');
    var hideNav = lb.items.length <= 1;
    lb.prev.classList.toggle('hidden', hideNav);
    lb.next.classList.toggle('hidden', hideNav);
  }

  function openLightbox(items, startIdx) {
    ensureLightbox();
    lb.items = items;
    showLightboxIndex(startIdx);
    lb.el.classList.add('is-open');
    document.body.style.overflow = 'hidden';
  }

  function closeLightbox() {
    if (!lb.el || !lb.el.classList.contains('is-open')) return;
    lb.el.classList.remove('is-open');
    document.body.style.overflow = '';
  }

  function stepLightbox(delta) {
    if (lb.items.length > 1) showLightboxIndex(lb.idx + delta);
  }

  function initLightbox() {
    var imgs = Array.prototype.slice.call(document.querySelectorAll('.article-cover, .prose img'));
    if (!imgs.length) return;
    var items = imgs.map(function (im) {
      return { src: im.currentSrc || im.src, alt: im.alt || '' };
    });
    imgs.forEach(function (im, idx) {
      if (im.dataset.lbBound) return;
      im.dataset.lbBound = '1';
      im.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        openLightbox(items, idx);
      });
    });
  }

  /* ---------------------------------------------------------
     7. Smooth Image Fade-In + Staggered Reveal + Code Copy + Search
     --------------------------------------------------------- */
  function enhanceImages() {
    document.querySelectorAll('.post-cover, .article-cover, .prose img').forEach(function (im) {
      if (im.complete && im.naturalWidth > 0) {
        im.classList.remove('img-fade');
        return;
      }
      im.classList.add('img-fade');
      var done = function () {
        im.classList.add('is-loaded');
        recalcMetrics();
      };
      im.addEventListener('load', done, { once: true });
      im.addEventListener('error', done, { once: true });
    });
  }

  function animateStageCards() {
    if (reducedMotion || !stage) return;
    var items = stage.querySelectorAll('.reveal');
    items.forEach(function (el, idx) {
      el.style.animationDelay = Math.min(idx * 35, 175) + 'ms';
      el.classList.add('is-anim-in');
      el.addEventListener('animationend', function () {
        el.classList.remove('is-anim-in');
        el.style.animationDelay = '';
      }, { once: true });
    });
  }

  function enhanceCodeBlocks() {
    document.querySelectorAll('.prose pre').forEach(function (pre) {
      if (pre.parentElement && pre.parentElement.classList.contains('code-wrap')) return;
      var wrap = document.createElement('div');
      wrap.className = 'code-wrap';
      pre.parentNode.insertBefore(wrap, pre);
      wrap.appendChild(pre);

      var bar = document.createElement('div');
      bar.className = 'code-bar';
      bar.innerHTML = '<span class="code-dots"><i></i><i></i><i></i></span>';
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'copy-btn';
      btn.textContent = '复制';
      btn.addEventListener('click', function () {
        var code = pre.querySelector('code');
        var text = code ? code.innerText : pre.innerText;
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(function () {
            btn.textContent = '已复制 ✦';
            btn.classList.add('is-copied');
            setTimeout(function () {
              btn.textContent = '复制';
              btn.classList.remove('is-copied');
            }, 1500);
          }).catch(function () {});
        }
      });
      bar.appendChild(btn);
      wrap.appendChild(bar);
    });
  }

  function initSearch() {
    var searchInput = document.getElementById('search-input');
    var resultsBox = document.getElementById('search-results');
    var searchForm = document.getElementById('search-form');
    if (!searchInput || !resultsBox) return;

    function esc(s) {
      return String(s || '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
    }

    function renderHits(list, q) {
      if (!q) {
        resultsBox.innerHTML = '';
        recalcMetrics();
        return;
      }
      var needle = q.toLowerCase();
      var hits = list.filter(function (p) {
        return (
          (p.title || '').toLowerCase().indexOf(needle) !== -1 ||
          (p.summary || '').toLowerCase().indexOf(needle) !== -1 ||
          (p.category || '').toLowerCase().indexOf(needle) !== -1 ||
          (p.tags || '').toLowerCase().indexOf(needle) !== -1
        );
      });
      if (!hits.length) {
        resultsBox.innerHTML = '<div class="empty-state">没有找到与「' + esc(q) + '」相关的笔记呢，换个关键词试试吧～</div>';
        recalcMetrics();
        return;
      }
      resultsBox.innerHTML = hits.map(function (p) {
        var tagsHtml = (p.tags || '')
          .split(',')
          .map(function (t) { return t.trim(); })
          .filter(Boolean)
          .map(function (t) {
            return '<a class="tag-chip" href="/tag/' + encodeURIComponent(t) + '/">#' + esc(t) + '</a>';
          })
          .join('');
        var coverHtml = p.cover
          ? '<a class="post-cover-link" href="/post/' + esc(p.slug) + '/"><img class="post-cover" src="' + esc(p.cover) + '" alt="' + esc(p.title) + '" loading="lazy" decoding="async"></a>'
          : '';
        var catHtml = p.category
          ? '<a class="cat-badge" href="/category/' + encodeURIComponent(p.category) + '/">✦ ' + esc(p.category) + '</a>'
          : '';
        return (
          '<article class="post-card">' +
          '<div class="ribbon-corner" aria-hidden="true"><span>★</span></div>' +
          coverHtml +
          '<div class="post-meta">' + catHtml + '<time>' + esc(p.date) + '</time></div>' +
          '<h2 class="post-card-title"><a href="/post/' + esc(p.slug) + '/">' + esc(p.title) + '</a></h2>' +
          '<p class="post-summary">' + esc(p.summary) + '</p>' +
          '<div class="post-card-foot"><div class="tag-row">' + tagsHtml + '</div>' +
          '<a class="read-more" href="/post/' + esc(p.slug) + '/">阅读全文 <span aria-hidden="true">&rarr;</span></a></div>' +
          '</article>'
        );
      }).join('');
      enhanceImages();
      recalcMetrics();
    }

    function runSearch(q) {
      if (searchIndexCache) {
        renderHits(searchIndexCache, q);
        return;
      }
      fetch('/search-index.json')
        .then(function (r) { return r.json(); })
        .then(function (data) {
          searchIndexCache = Array.isArray(data) ? data : [];
          renderHits(searchIndexCache, q);
        })
        .catch(function () {});
    }

    searchInput.addEventListener('input', function () {
      runSearch(searchInput.value.trim());
    });

    if (searchForm) {
      searchForm.addEventListener('submit', function (e) {
        e.preventDefault();
        var q = searchInput.value.trim();
        var url = q ? ('/search/?q=' + encodeURIComponent(q)) : '/search/';
        history.replaceState({}, '', url);
        runSearch(q);
      });
    }

    var params = new URLSearchParams(window.location.search);
    var initQ = (params.get('q') || '').trim();
    if (initQ && !searchInput.value) {
      searchInput.value = initQ;
      runSearch(initQ);
    }
  }

  function updateCatBarState() {
    var cur = decodeURIComponent(window.location.pathname).replace(/\/+$/, '') || '/';
    var activePill = null;
    document.querySelectorAll('.cat-bar .cat-pill').forEach(function (a) {
      var href = decodeURIComponent(new URL(a.href, window.location.origin).pathname).replace(/\/+$/, '') || '/';
      var on = cur === href;
      a.classList.toggle('is-active', on);
      if (on) activePill = a;
      var cntEl = a.querySelector('.cat-pill-cnt');
      if (cntEl && cntEl.textContent.trim() === '0') {
        a.classList.add('is-empty');
      }
    });
    if (activePill && activePill.scrollIntoView) {
      try { activePill.scrollIntoView({ inline: 'nearest', block: 'nearest' }); } catch (_) {}
    }
  }

  function hydratePage(animate) {
    if (animate) animateStageCards();
    enhanceImages();
    enhanceCodeBlocks();
    initLightbox();
    bindAvatarBoing();
    initSearch();
    updateNavState();
    updateCatBarState();
    requestAnimationFrame(recalcMetrics);
  }

  /* ---------------------------------------------------------
     8. 60fps Single-Layer Zero-Hard-Cut PJAX + Whole-Card Tap
     --------------------------------------------------------- */
  function isInternalPageLink(a) {
    if (!a || !a.href) return false;
    if (a.hasAttribute('data-no-pjax') || a.hasAttribute('download')) return false;
    if (a.target && a.target !== '_self') return false;
    var url;
    try { url = new URL(a.href, window.location.origin); } catch (_) { return false; }
    if (url.origin !== window.location.origin) return false;
    if (url.pathname.indexOf('/static/') === 0) return false;
    if (url.pathname.indexOf('/uploads/') === 0) return false;
    if (url.pathname.indexOf('/api/') === 0) return false;
    if (/\.(xml|json|ico|png|jpg|jpeg|webp|gif|svg|css|js|pdf|zip)$/i.test(url.pathname)) return false;
    return true;
  }

  var PREFETCH_TTL = 30000;
  var PREFETCH_MAX = 24;

  function fetchHtml(urlStr) {
    var now = Date.now();
    var cached = prefetchCache.get(urlStr);
    if (cached && now - cached.ts < PREFETCH_TTL) return cached.promise;
    if (cached) prefetchCache.delete(urlStr);
    var p = fetch(urlStr, { headers: { 'X-AsmBlog-PJAX': '1' } })
      .then(function (resp) {
        if (!resp.ok && resp.status !== 404) throw new Error('HTTP ' + resp.status);
        var ct = resp.headers.get('content-type') || '';
        if (ct.indexOf('text/html') === -1) throw new Error('Not HTML');
        return resp.text();
      });
    // A failed (pre)fetch must never poison later navigations: evict it right away.
    p.catch(function () {
      var cur = prefetchCache.get(urlStr);
      if (cur && cur.promise === p) prefetchCache.delete(urlStr);
    });
    prefetchCache.set(urlStr, { ts: now, promise: p });
    // Bounded LRU-ish eviction (Map keeps insertion order -> oldest first).
    while (prefetchCache.size > PREFETCH_MAX) {
      prefetchCache.delete(prefetchCache.keys().next().value);
    }
    return p;
  }

  document.addEventListener('pointerenter', function (e) {
    if (!e.target || !e.target.closest) return;
    var a = e.target.closest('a');
    if (!isInternalPageLink(a)) return;
    var u = new URL(a.href, window.location.origin);
    if (u.pathname === window.location.pathname && u.search === window.location.search) return;
    fetchHtml(u.href).catch(function () {});
  }, true);

  function smoothNavigate(urlObj, push) {
    closeLightbox();
    if (!stage || isNavigating) {
      window.location.href = urlObj.href;
      return;
    }
    if (urlObj.pathname === window.location.pathname && urlObj.search === window.location.search) {
      if (urlObj.hash) {
        var anchor = document.querySelector(urlObj.hash);
        if (anchor) anchor.scrollIntoView({ behavior: reducedMotion ? 'auto' : 'smooth' });
      } else {
        window.scrollTo({ top: 0, behavior: reducedMotion ? 'auto' : 'smooth' });
      }
      return;
    }

    isNavigating = true;
    updateNavState(urlObj.pathname);
    startLoader();

    var leaveWait = new Promise(function (resolve) {
      stage.classList.remove('is-entering');
      stage.classList.add('is-leaving');
      setTimeout(resolve, reducedMotion ? 10 : 140);
    });

    Promise.all([fetchHtml(urlObj.href), leaveWait])
      .then(function (results) {
        var html = results[0];
        var doc = new DOMParser().parseFromString(html, 'text/html');
        var nextStage = doc.getElementById('pjax-stage');
        if (!nextStage) {
          window.location.href = urlObj.href;
          return;
        }

        stage.innerHTML = nextStage.innerHTML;
        document.title = doc.title || document.title;
        if (push) history.pushState({ url: urlObj.href }, '', urlObj.href);

        if (urlObj.hash) {
          var targetEl = document.querySelector(urlObj.hash);
          if (targetEl) targetEl.scrollIntoView({ behavior: 'auto' });
          else window.scrollTo(0, 0);
        } else {
          window.scrollTo(0, 0);
        }

        stage.classList.remove('is-leaving');
        void stage.offsetWidth;
        stage.classList.add('is-entering');
        setTimeout(function () { stage.classList.remove('is-entering'); }, 280);

        finishLoader();
        isNavigating = false;
        hydratePage(true);
      })
      .catch(function () {
        finishLoader();
        isNavigating = false;
        window.location.href = urlObj.href;
      });
  }

  document.addEventListener('click', function (e) {
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    var a = e.target.closest('a');
    if (a) {
      if (!isInternalPageLink(a)) return;
      var urlObj = new URL(a.href, window.location.origin);
      e.preventDefault();
      smoothNavigate(urlObj, true);
      return;
    }
    // Whole-card tap on .post-card (ignores buttons or active text selection)
    if (e.target.closest('button, input, textarea')) return;
    var sel = window.getSelection && window.getSelection();
    if (sel && sel.toString().length > 0) return;
    var card = e.target.closest('.post-card');
    if (card) {
      var titleLink = card.querySelector('.post-card-title a');
      if (titleLink && isInternalPageLink(titleLink)) {
        e.preventDefault();
        smoothNavigate(new URL(titleLink.href, window.location.origin), true);
      }
    }
  });

  window.addEventListener('popstate', function () {
    smoothNavigate(new URL(window.location.href), false);
  });

  document.addEventListener('keydown', function (e) {
    if (lb.el && lb.el.classList.contains('is-open')) {
      if (e.key === 'Escape') { e.preventDefault(); closeLightbox(); }
      else if (e.key === 'ArrowLeft') { e.preventDefault(); stepLightbox(-1); }
      else if (e.key === 'ArrowRight') { e.preventDefault(); stepLightbox(1); }
      return;
    }
    if (e.key === '/' && document.activeElement.tagName !== 'INPUT' && document.activeElement.tagName !== 'TEXTAREA') {
      var inp = document.getElementById('search-input');
      if (inp) {
        e.preventDefault();
        inp.focus();
      } else {
        e.preventDefault();
        smoothNavigate(new URL('/search/', window.location.origin), true);
      }
    }
  });

  hydratePage(false);
  if (document.fonts && document.fonts.ready) {
    document.fonts.ready.then(function () { updateNavState(); });
  }
})();
