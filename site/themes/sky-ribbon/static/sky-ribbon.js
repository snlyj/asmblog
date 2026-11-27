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
     1. Zero-Reflow GPU Scroll Progress + SVG Ring + TOC Spy (Single RAF)
     --------------------------------------------------------- */
  var maxScroll = 1;
  var scrollTicking = false;
  var backTopShown = false;
  var fabsShown = false;
  var tocEntries = [];
  var activeTocId = '';
  var toastEl = null;
  var toastTimer = null;
  var scrollMemo = new Map();
  var currentUrlKey = window.location.pathname + window.location.search;
  if ('scrollRestoration' in history) {
    try { history.scrollRestoration = 'manual'; } catch (_) {}
  }

  function showToast(msg) {
    if (!toastEl) {
      toastEl = document.createElement('div');
      toastEl.id = 'sky-toast';
      toastEl.className = 'sky-toast';
      toastEl.setAttribute('role', 'status');
      toastEl.setAttribute('aria-live', 'polite');
      document.body.appendChild(toastEl);
    }
    toastEl.textContent = msg;
    toastEl.classList.add('is-shown');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () {
      if (toastEl) toastEl.classList.remove('is-shown');
    }, 1800);
  }

  function copyText(text, onOk) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () {
        if (onOk) onOk();
      }).catch(function () { fallbackCopy(text, onOk); });
    } else {
      fallbackCopy(text, onOk);
    }
  }

  function fallbackCopy(text, onOk) {
    try {
      var ta = document.createElement('textarea');
      ta.value = text;
      ta.setAttribute('readonly', '');
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      var ok = document.execCommand('copy');
      document.body.removeChild(ta);
      if (ok && onOk) onOk();
    } catch (_) {}
  }

  function recalcTocOffsets() {
    if (!tocEntries.length) return;
    var sy = window.scrollY || root.scrollTop || 0;
    for (var i = 0; i < tocEntries.length; i++) {
      tocEntries[i].top = tocEntries[i].el.getBoundingClientRect().top + sy;
    }
  }

  function syncTocActive(y) {
    if (!tocEntries.length) return;
    var cur = tocEntries[0].id;
    var pivot = y + 110;
    for (var i = 0; i < tocEntries.length; i++) {
      if (tocEntries[i].top <= pivot) cur = tocEntries[i].id;
      else break;
    }
    if (cur === activeTocId) return;
    activeTocId = cur;
    for (var j = 0; j < tocEntries.length; j++) {
      var on = tocEntries[j].id === cur;
      var links = tocEntries[j].links;
      for (var k = 0; k < links.length; k++) {
        links[k].classList.toggle('is-active', on);
      }
    }
  }

  function recalcMetrics() {
    maxScroll = Math.max(1, root.scrollHeight - window.innerHeight);
    recalcTocOffsets();
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
    var fabs = document.getElementById('article-fabs');
    if (fabs) {
      var showFabs = y > 260;
      if (showFabs !== fabsShown || fabs.classList.contains('is-shown') !== showFabs) {
        fabsShown = showFabs;
        fabs.classList.toggle('is-shown', showFabs);
      }
    }
    syncTocActive(y);
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
    syncCatBarFade();
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
    if (p.indexOf('/moments') === 0) return '/moments';
    if (p.indexOf('/gallery') === 0) return '/gallery';
    if (p.indexOf('/archive') === 0) return '/archive';
    if (p.indexOf('/tags') === 0 || p.indexOf('/tag/') === 0) return '/tags';
    if (p.indexOf('/about') === 0) return '/about';
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

  function giscusThemeFor(mode) {
    return mode === 'dark' ? 'noborder_dark' : 'noborder_light';
  }

  function syncGiscusTheme(mode) {
    var iframe = document.querySelector('iframe.giscus-frame');
    if (!iframe || !iframe.contentWindow) return;
    try {
      iframe.contentWindow.postMessage(
        { giscus: { setConfig: { theme: giscusThemeFor(mode) } } },
        'https://giscus.app'
      );
    } catch (_) {}
  }

  function applyTheme(next) {
    root.setAttribute('data-theme', next);
    store('asmblog-theme', next);
    syncGiscusTheme(next);
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
        showToast('已开启点击星光 ✦');
      } else {
        root.setAttribute('data-fx', 'off');
        store('asmblog-fx', 'off');
        showToast('已关闭点击星光');
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
    if (e.target && e.target.closest && e.target.closest('#img-lightbox, #cmd-search, #toc-sheet, #bgm-dock')) return;
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
     6. Zero-Blur GPU Gallery Lightbox (HD Original + Pan + Pinch + Wheel + Swipe-Down)
     --------------------------------------------------------- */
  var lb = {
    el: null, img: null, cap: null, badge: null, orig: null, zoomBtn: null, prev: null, next: null,
    items: [], idx: 0, lastTap: 0, zoomed: false, loadSeq: 0,
    scale: 1, tx: 0, ty: 0, ptrs: new Map(),
    pinchDist: 0, pinchMidX: 0, pinchMidY: 0,
    dragAxis: '', startX: 0, startY: 0, startTx: 0, startTy: 0,
    moved: false, suppressClick: false
  };
  var loadedOrigs = new Set();

  function extractOrigUrl(urlStr) {
    if (!urlStr) return '';
    try {
      var u = new URL(urlStr, window.location.origin);
      var o = (u.searchParams.get('orig') || '').trim();
      if (o && (o.indexOf('/') === 0 || /^https?:\/\//i.test(o))) return o;
    } catch (_) {}
    return '';
  }

  function clampLightboxPan() {
    if (!lb.img) return;
    if (lb.scale <= 1.02) {
      lb.tx = 0;
      lb.ty = 0;
      return;
    }
    var bw = lb.img.offsetWidth || 0;
    var bh = lb.img.offsetHeight || 0;
    var maxX = Math.max(0, (bw * lb.scale - window.innerWidth * 0.92) / 2);
    var maxY = Math.max(0, (bh * lb.scale - window.innerHeight * 0.86) / 2);
    if (lb.tx > maxX) lb.tx = maxX;
    if (lb.tx < -maxX) lb.tx = -maxX;
    if (lb.ty > maxY) lb.ty = maxY;
    if (lb.ty < -maxY) lb.ty = -maxY;
  }

  function applyLightboxTransform(animate) {
    if (!lb.img) return;
    lb.zoomed = lb.scale > 1.04;
    lb.img.classList.toggle('is-anim', !!animate && !reducedMotion);
    lb.img.classList.toggle('is-zoomed', lb.zoomed);
    lb.img.style.transform =
      'translate3d(' + lb.tx.toFixed(1) + 'px,' + lb.ty.toFixed(1) + 'px,0) scale(' + lb.scale.toFixed(4) + ')';
    if (lb.zoomBtn) {
      lb.zoomBtn.classList.toggle('is-active', lb.zoomed);
      lb.zoomBtn.textContent = lb.zoomed ? ('🔍 ' + lb.scale.toFixed(1) + 'x 还原') : '🔍 放大';
    }
  }

  function zoomLightboxAt(nextScale, clientX, clientY, animate) {
    if (!lb.img) return;
    var clamped = Math.max(1, Math.min(4, nextScale));
    if (clamped <= 1.03) {
      lb.scale = 1;
      lb.tx = 0;
      lb.ty = 0;
      applyLightboxTransform(animate);
      return;
    }
    var oldScale = lb.scale || 1;
    if (typeof clientX === 'number' && typeof clientY === 'number') {
      var r = lb.img.getBoundingClientRect();
      var cx = r.left + r.width / 2 - lb.tx;
      var cy = r.top + r.height / 2 - lb.ty;
      var dx = (clientX - (cx + lb.tx)) / oldScale;
      var dy = (clientY - (cy + lb.ty)) / oldScale;
      lb.tx = clientX - cx - dx * clamped;
      lb.ty = clientY - cy - dy * clamped;
    }
    lb.scale = clamped;
    clampLightboxPan();
    applyLightboxTransform(animate);
  }

  function setLightboxZoom(on, clientX, clientY) {
    if (!lb.img) return;
    if (on) {
      zoomLightboxAt(2.2, clientX, clientY, true);
    } else {
      lb.scale = 1;
      lb.tx = 0;
      lb.ty = 0;
      applyLightboxTransform(true);
    }
  }

  function preloadAdjacent(idx) {
    if (lb.items.length <= 1) return;
    var neighbors = [(idx + 1) % lb.items.length, (idx - 1 + lb.items.length) % lb.items.length];
    neighbors.forEach(function (ni) {
      var it = lb.items[ni];
      if (!it || !it.src) return;
      var pre = new Image();
      pre.decoding = 'async';
      pre.src = it.src;
    });
  }

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
      '<img class="lightbox-img" alt="" draggable="false">' +
      '<button class="lightbox-nav lightbox-next" type="button" aria-label="下一张">›</button>' +
      '<div class="lightbox-bar"><span class="lightbox-cap"></span><span class="lightbox-badge hidden"></span><button class="lightbox-zoom" type="button" aria-label="缩放预览">🔍 放大</button><a class="lightbox-orig" target="_blank" rel="noopener">原图 ↗</a></div>';
    document.body.appendChild(wrap);

    lb.el = wrap;
    lb.img = wrap.querySelector('.lightbox-img');
    lb.cap = wrap.querySelector('.lightbox-cap');
    lb.badge = wrap.querySelector('.lightbox-badge');
    lb.orig = wrap.querySelector('.lightbox-orig');
    lb.zoomBtn = wrap.querySelector('.lightbox-zoom');
    lb.prev = wrap.querySelector('.lightbox-prev');
    lb.next = wrap.querySelector('.lightbox-next');

    wrap.querySelector('.lightbox-close').addEventListener('click', closeLightbox);
    lb.prev.addEventListener('click', function (e) { e.stopPropagation(); stepLightbox(-1); });
    lb.next.addEventListener('click', function (e) { e.stopPropagation(); stepLightbox(1); });
    lb.zoomBtn.addEventListener('click', function (e) {
      e.stopPropagation();
      setLightboxZoom(!lb.zoomed);
    });
    lb.img.addEventListener('dblclick', function (e) {
      e.preventDefault();
      e.stopPropagation();
      setLightboxZoom(!lb.zoomed, e.clientX, e.clientY);
    });
    wrap.addEventListener('click', function (e) {
      if (lb.suppressClick) { lb.suppressClick = false; return; }
      if (e.target === wrap) closeLightbox();
    });

    wrap.addEventListener('wheel', function (e) {
      if (!wrap.classList.contains('is-open')) return;
      e.preventDefault();
      var factor = e.deltaY < 0 ? 1.15 : 0.87;
      zoomLightboxAt(lb.scale * factor, e.clientX, e.clientY, false);
    }, { passive: false });

    wrap.addEventListener('pointerdown', function (e) {
      if (!wrap.classList.contains('is-open')) return;
      if (e.button !== 0 && e.pointerType === 'mouse') return;
      if (e.target && e.target.closest && e.target.closest('button, a, .lightbox-bar')) return;
      if (e.target !== lb.img && lb.scale <= 1.04) return;
      if (e.pointerType !== 'mouse') e.preventDefault();
      lb.suppressClick = false;
      lb.ptrs.set(e.pointerId, { x: e.clientX, y: e.clientY, captured: false });
      if (lb.ptrs.size === 1) {
        lb.startX = e.clientX;
        lb.startY = e.clientY;
        lb.startTx = lb.tx;
        lb.startTy = lb.ty;
        lb.moved = false;
        lb.dragAxis = lb.scale > 1.04 ? 'pan' : '';
      } else if (lb.ptrs.size === 2) {
        var pts = Array.from(lb.ptrs.values());
        lb.pinchDist = Math.hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y);
        lb.pinchMidX = (pts[0].x + pts[1].x) / 2;
        lb.pinchMidY = (pts[0].y + pts[1].y) / 2;
        lb.dragAxis = 'pinch';
        lb.moved = true;
        lb.img.classList.remove('is-anim');
        try { wrap.setPointerCapture(e.pointerId); } catch (_) {}
      }
    });

    wrap.addEventListener('pointermove', function (e) {
      var curPtr = lb.ptrs.get(e.pointerId);
      if (!curPtr) return;
      e.preventDefault();
      curPtr.x = e.clientX;
      curPtr.y = e.clientY;
      if (lb.ptrs.size === 2) {
        var pts = Array.from(lb.ptrs.values());
        var dist = Math.hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y);
        var mx = (pts[0].x + pts[1].x) / 2;
        var my = (pts[0].y + pts[1].y) / 2;
        if (lb.pinchDist > 10 && dist > 10) {
          lb.tx += (mx - lb.pinchMidX);
          lb.ty += (my - lb.pinchMidY);
          zoomLightboxAt(lb.scale * (dist / lb.pinchDist), mx, my, false);
        }
        lb.pinchDist = dist;
        lb.pinchMidX = mx;
        lb.pinchMidY = my;
        return;
      }
      if (lb.ptrs.size !== 1) return;
      var dx = e.clientX - lb.startX;
      var dy = e.clientY - lb.startY;
      if (Math.hypot(dx, dy) > 5) {
        lb.moved = true;
        if (!curPtr.captured) {
          curPtr.captured = true;
          try { wrap.setPointerCapture(e.pointerId); } catch (_) {}
        }
        if (lb.dragAxis === 'pan') lb.img.classList.add('is-dragging');
      }
      if (!lb.moved) return;

      if (lb.dragAxis === 'pan') {
        lb.tx = lb.startTx + dx;
        lb.ty = lb.startTy + dy;
        clampLightboxPan();
        applyLightboxTransform(false);
        return;
      }
      if (!lb.dragAxis && Math.hypot(dx, dy) > 10) {
        if (Math.abs(dx) > Math.abs(dy) && lb.items.length > 1) lb.dragAxis = 'x';
        else if (dy > 0) lb.dragAxis = 'y';
        else lb.dragAxis = 'none';
      }
      if (lb.dragAxis === 'x') {
        lb.tx = dx * 0.72;
        lb.ty = 0;
        applyLightboxTransform(false);
      } else if (lb.dragAxis === 'y') {
        var pull = Math.max(0, dy);
        lb.tx = dx * 0.25;
        lb.ty = pull;
        lb.el.classList.add('is-swiping');
        var sc = Math.max(0.82, 1 - pull / 950);
        lb.img.classList.remove('is-anim');
        lb.img.style.transform =
          'translate3d(' + lb.tx.toFixed(1) + 'px,' + pull.toFixed(1) + 'px,0) scale(' + sc.toFixed(4) + ')';
        lb.el.style.background = 'rgba(11, 18, 34, ' + Math.max(0.22, 0.92 - pull / 480).toFixed(3) + ')';
      }
    });

    function endLbPtr(e) {
      if (!lb.ptrs.has(e.pointerId)) return;
      lb.ptrs.delete(e.pointerId);
      if (lb.ptrs.size === 1) {
        var rem = lb.ptrs.values().next().value;
        lb.startX = rem.x;
        lb.startY = rem.y;
        lb.startTx = lb.tx;
        lb.startTy = lb.ty;
        lb.pinchDist = 0;
        lb.dragAxis = lb.scale > 1.04 ? 'pan' : '';
        return;
      }
      if (lb.ptrs.size > 0) return;

      lb.pinchDist = 0;
      lb.img.classList.remove('is-dragging');
      lb.el.classList.remove('is-swiping');
      lb.el.style.background = '';
      if (lb.moved) lb.suppressClick = true;

      var axis = lb.dragAxis;
      lb.dragAxis = '';
      if (!lb.moved && e.pointerType === 'touch') {
        var now = Date.now();
        if (now - lb.lastTap < 280) {
          lb.lastTap = 0;
          setLightboxZoom(!lb.zoomed, e.clientX, e.clientY);
        } else {
          lb.lastTap = now;
        }
      } else if (axis === 'x') {
        if (Math.abs(lb.tx) > 46 && lb.items.length > 1) {
          stepLightbox(lb.tx < 0 ? 1 : -1);
        } else {
          lb.tx = 0;
          applyLightboxTransform(true);
        }
      } else if (axis === 'y') {
        if (lb.ty > 92) {
          closeLightbox();
        } else {
          lb.tx = 0;
          lb.ty = 0;
          applyLightboxTransform(true);
        }
      } else if (axis === 'pan' || axis === 'pinch') {
        if (lb.scale <= 1.04) {
          setLightboxZoom(false);
        } else {
          clampLightboxPan();
          applyLightboxTransform(true);
        }
      }
    }
    wrap.addEventListener('pointerup', endLbPtr);
    wrap.addEventListener('pointercancel', endLbPtr);
  }

  function setLightboxBadge(text, isHd) {
    if (!lb.badge) return;
    if (!text) {
      lb.badge.textContent = '';
      lb.badge.className = 'lightbox-badge hidden';
      return;
    }
    lb.badge.textContent = text;
    lb.badge.className = 'lightbox-badge' + (isHd ? ' is-hd' : '');
  }

  function showLightboxIndex(i) {
    if (!lb.items.length) return;
    lb.scale = 1;
    lb.tx = 0;
    lb.ty = 0;
    lb.ptrs.clear();
    lb.dragAxis = '';
    applyLightboxTransform(false);

    lb.idx = (i + lb.items.length) % lb.items.length;
    var item = lb.items[lb.idx];
    var seq = ++lb.loadSeq;
    var targetOrig = item.orig || '';
    lb.img.alt = item.alt || '';
    lb.orig.href = targetOrig || item.src;
    var countTxt = lb.items.length > 1 ? ('(' + (lb.idx + 1) + ' / ' + lb.items.length + ') ') : '';
    lb.cap.textContent = countTxt + (item.alt || '');
    var hideNav = lb.items.length <= 1;
    lb.prev.classList.toggle('hidden', hideNav);
    lb.next.classList.toggle('hidden', hideNav);

    if (targetOrig && targetOrig !== item.src) {
      if (loadedOrigs.has(targetOrig)) {
        lb.img.src = targetOrig;
        setLightboxBadge('✦ 完整高清原图', true);
      } else {
        // Show cached fast preview instantly, then upgrade seamlessly to full uncropped original
        lb.img.src = item.src;
        setLightboxBadge('⏳ 正在加载完整原图…', false);
        var hi = new Image();
        hi.decoding = 'async';
        hi.onload = function () {
          loadedOrigs.add(targetOrig);
          if (lb.loadSeq !== seq) return;
          lb.img.src = targetOrig;
          setLightboxBadge('✦ 完整高清原图', true);
        };
        hi.onerror = function () {
          if (lb.loadSeq !== seq) return;
          setLightboxBadge('', false);
        };
        hi.src = targetOrig;
      }
    } else {
      lb.img.src = item.src;
      setLightboxBadge('', false);
    }
    preloadAdjacent(lb.idx);
  }

  function openLightbox(items, startIdx) {
    ensureLightbox();
    closeTocSheet();
    closeCmdSearch();
    document.querySelectorAll('video').forEach(function (v) { try { v.pause(); } catch (_) {} });
    lb.items = items;
    showLightboxIndex(startIdx);
    lb.el.classList.add('is-open');
    syncBodyLock();
  }

  function closeLightbox() {
    if (!lb.el || !lb.el.classList.contains('is-open')) return;
    lb.loadSeq++;
    lb.ptrs.clear();
    lb.dragAxis = '';
    lb.el.classList.remove('is-swiping');
    lb.el.style.background = '';
    setLightboxZoom(false);
    lb.el.classList.remove('is-open');
    syncBodyLock();
  }

  function stepLightbox(delta) {
    if (lb.items.length > 1) showLightboxIndex(lb.idx + delta);
  }

  function bindLightboxGroup(selector) {
    var imgs = Array.prototype.slice.call(document.querySelectorAll(selector));
    if (!imgs.length) return;
    var items = imgs.map(function (im) {
      var rawSrc = im.getAttribute('src') || im.currentSrc || im.src;
      return {
        src: im.currentSrc || im.src,
        orig: extractOrigUrl(rawSrc),
        alt: im.alt || ''
      };
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

  function initLightbox() {
    bindLightboxGroup('.article-cover, .prose img');
    bindLightboxGroup('.hero-banner-img');
    bindLightboxGroup('.about-avatar-img');
    bindLightboxGroup('.not-found-img');
  }

  /* ---------------------------------------------------------
     7. Smooth Image Fade-In + Captions + TOC + Code + Search + Archive
     --------------------------------------------------------- */
  function enhanceImages() {
    document.querySelectorAll('.prose img').forEach(function (im) {
      var alt = (im.getAttribute('alt') || '').trim();
      if (alt.length >= 2 && !/\.(jpg|jpeg|png|webp|gif|svg)$/i.test(alt) && !/^(img|image|photo|pic|插图|图片)$/i.test(alt)) {
        if (!im.closest('figure')) {
          var fig = document.createElement('figure');
          fig.className = 'prose-fig';
          var cap = document.createElement('figcaption');
          cap.className = 'prose-cap';
          cap.textContent = '✦ ' + alt;
          im.parentNode.insertBefore(fig, im);
          fig.appendChild(im);
          fig.appendChild(cap);
        }
      }
    });
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

  function enhanceVideos() {
    document.querySelectorAll('.prose video.prose-video').forEach(function (vid) {
      if (vid.dataset.vidEnhanced) return;
      vid.dataset.vidEnhanced = '1';
      var rawSrc = vid.getAttribute('src') || '';
      if (rawSrc) {
        try {
          var u = new URL(rawSrc, window.location.origin);
          var poster = (u.searchParams.get('poster') || '').trim();
          if (poster && (poster.indexOf('/') === 0 || /^https?:\/\//i.test(poster))) {
            vid.setAttribute('poster', poster);
          }
        } catch (_) {}
      }
      // Mutual auto-pause so multi-video posts and BGM never overlap audio
      vid.addEventListener('play', function () {
        if (typeof pauseBgm === 'function') pauseBgm();
        document.querySelectorAll('video').forEach(function (other) {
          if (other !== vid && !other.paused) {
            try { other.pause(); } catch (_) {}
          }
        });
      });
      var title = (vid.getAttribute('title') || '').trim();
      if (title.length >= 2 && !/\.(mp4|webm|mov|m4v|ogg|ogv)$/i.test(title) && !/^(video|clip|视频)$/i.test(title)) {
        if (!vid.closest('figure')) {
          var fig = document.createElement('figure');
          fig.className = 'prose-video-fig';
          var cap = document.createElement('figcaption');
          cap.className = 'prose-cap';
          cap.textContent = '🎬 ' + title;
          vid.parentNode.insertBefore(fig, vid);
          fig.appendChild(vid);
          fig.appendChild(cap);
        }
      }
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

      var code = pre.querySelector('code');
      var langMatch = code ? (code.className || '').match(/\b(?:lang|language)-([a-z0-9_+#.-]+)\b/i) : null;
      var bar = document.createElement('div');
      bar.className = 'code-bar';
      var left = document.createElement('span');
      left.className = 'code-left';
      left.innerHTML = '<span class="code-dots"><i></i><i></i><i></i></span>';
      if (langMatch && langMatch[1]) {
        var langTag = document.createElement('span');
        langTag.className = 'code-lang';
        langTag.textContent = langMatch[1];
        left.appendChild(langTag);
      }
      bar.appendChild(left);

      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'copy-btn';
      btn.textContent = '复制';
      btn.addEventListener('click', function () {
        var text = code ? code.innerText : pre.innerText;
        copyText(text, function () {
          btn.textContent = '已复制 ✦';
          btn.classList.add('is-copied');
          setTimeout(function () {
            btn.textContent = '复制';
            btn.classList.remove('is-copied');
          }, 1500);
        });
      });
      bar.appendChild(btn);
      wrap.appendChild(bar);
    });
  }

  var tocSheetEl = null;
  var tocSheetBody = null;
  var cmdEl = null;
  var cmdInput = null;
  var cmdBody = null;
  var cmdHits = [];
  var cmdActiveIdx = 0;

  function syncBodyLock() {
    var locked =
      (lb.el && lb.el.classList.contains('is-open')) ||
      (tocSheetEl && tocSheetEl.classList.contains('is-open')) ||
      (cmdEl && cmdEl.classList.contains('is-open'));
    document.body.style.overflow = locked ? 'hidden' : '';
  }

  function ensureTocSheet() {
    if (tocSheetEl) return;
    var el = document.createElement('div');
    el.id = 'toc-sheet';
    el.className = 'toc-sheet';
    el.setAttribute('role', 'dialog');
    el.setAttribute('aria-modal', 'true');
    el.setAttribute('aria-label', '文章目录导航');
    el.innerHTML =
      '<div class="toc-sheet-panel">' +
      '<div class="toc-sheet-head"><span>✦ 本篇目录导航</span><button type="button" class="toc-sheet-close" aria-label="关闭目录">✕</button></div>' +
      '<div class="toc-sheet-body"></div>' +
      '</div>';
    document.body.appendChild(el);
    tocSheetEl = el;
    tocSheetBody = el.querySelector('.toc-sheet-body');
    el.querySelector('.toc-sheet-close').addEventListener('click', closeTocSheet);
    el.addEventListener('click', function (e) {
      if (e.target === el) closeTocSheet();
    });
  }

  function openTocSheet() {
    if (!tocSheetEl) return;
    tocSheetEl.classList.add('is-open');
    syncBodyLock();
    var act = tocSheetBody && tocSheetBody.querySelector('.toc-link.is-active');
    if (act && act.scrollIntoView) {
      try { act.scrollIntoView({ block: 'center', behavior: 'auto' }); } catch (_) {}
    }
  }

  function closeTocSheet() {
    if (!tocSheetEl || !tocSheetEl.classList.contains('is-open')) return;
    tocSheetEl.classList.remove('is-open');
    syncBodyLock();
  }

  function applyFontSize(sz, announce) {
    if (sz === 'sm' || sz === 'lg') {
      root.setAttribute('data-font', sz);
      store('asmblog-font', sz);
    } else {
      sz = 'md';
      root.removeAttribute('data-font');
      store('asmblog-font', 'md');
    }
    document.querySelectorAll('.font-btn[data-font-size]').forEach(function (b) {
      b.classList.toggle('is-active', b.getAttribute('data-font-size') === sz);
    });
    if (announce) {
      var label = sz === 'sm' ? '紧凑字号' : (sz === 'lg' ? '大字舒适模式' : '标准字号');
      showToast('已切换为' + label + ' ✦');
    }
    requestAnimationFrame(recalcMetrics);
  }

  function initArticleExtras() {
    tocEntries = [];
    activeTocId = '';
    fabsShown = false;
    closeTocSheet();

    var shareBtn = document.getElementById('share-post-btn');
    if (shareBtn && !shareBtn.dataset.bound) {
      shareBtn.dataset.bound = '1';
      shareBtn.addEventListener('click', function () {
        copyText(window.location.href, function () {
          showToast('文章链接已复制，快分享给同好吧 ✦');
        });
      });
    }

    // Reading font-size toggle (A- / A / A+)
    var curFont = root.getAttribute('data-font') || 'md';
    document.querySelectorAll('.font-btn[data-font-size]').forEach(function (b) {
      b.classList.toggle('is-active', b.getAttribute('data-font-size') === curFont);
      if (!b.dataset.bound) {
        b.dataset.bound = '1';
        b.addEventListener('click', function () {
          applyFontSize(b.getAttribute('data-font-size') || 'md', true);
        });
      }
    });

    var prose = document.querySelector('.article-card .prose');
    if (!prose) return;
    var feed = prose.closest('.feed-wrap');
    var headings = Array.prototype.slice.call(prose.querySelectorAll('h2, h3'));

    // Ensure unique IDs & append subtle heading anchor copy links
    headings.forEach(function (h, idx) {
      if (!h.id) h.id = 'sec-' + (idx + 1);
      if (!h.querySelector('.heading-anchor')) {
        var anc = document.createElement('a');
        anc.className = 'heading-anchor';
        anc.href = '#' + h.id;
        anc.setAttribute('data-no-pjax', 'true');
        anc.setAttribute('aria-label', '复制章节链接');
        anc.textContent = '#';
        anc.addEventListener('click', function (e) {
          e.preventDefault();
          var targetUrl = window.location.origin + window.location.pathname + '#' + h.id;
          history.replaceState(history.state, '', '#' + h.id);
          h.scrollIntoView({ behavior: reducedMotion ? 'auto' : 'smooth' });
          copyText(targetUrl, function () { showToast('章节链接已复制 ✦'); });
        });
        h.appendChild(anc);
      }
    });

    var hasToc = headings.length >= 2;
    var commentsCard = document.getElementById('comments-card');

    if (hasToc) {
      var slot = document.getElementById('article-toc-slot');
      if (slot && feed && !slot.dataset.tocBuilt) {
        slot.dataset.tocBuilt = '1';

        function makeTocList(onPick) {
          var ol = document.createElement('ol');
          ol.className = 'toc-list';
          headings.forEach(function (h, idx) {
            var li = document.createElement('li');
            li.className = 'toc-item' + (h.tagName === 'H3' ? ' is-sub' : '');
            var a = document.createElement('a');
            a.className = 'toc-link';
            a.href = '#' + h.id;
            a.setAttribute('data-no-pjax', 'true');
            var clone = h.cloneNode(true);
            var rm = clone.querySelector('.heading-anchor');
            if (rm) rm.remove();
            a.textContent = (clone.textContent || '').trim();
            a.addEventListener('click', function (e) {
              e.preventDefault();
              if (onPick) onPick();
              history.replaceState(history.state, '', '#' + h.id);
              h.scrollIntoView({ behavior: reducedMotion ? 'auto' : 'smooth' });
            });
            li.appendChild(a);
            ol.appendChild(li);
            if (!tocEntries[idx]) tocEntries[idx] = { el: h, id: h.id, top: 0, links: [] };
            tocEntries[idx].links.push(a);
          });
          return ol;
        }

        // Mobile / narrow collapsible TOC pill
        var det = document.createElement('details');
        det.className = 'toc-mobile';
        var sum = document.createElement('summary');
        sum.innerHTML = '<span>✦ 本篇目录</span><span class="toc-mobile-meta">' + headings.length + ' 节 <span class="toc-chevron" aria-hidden="true">▾</span></span>';
        det.appendChild(sum);
        det.appendChild(makeTocList(function () { det.open = false; }));
        slot.appendChild(det);

        // Wide desktop floating TOC card (lives inside #pjax-stage -> auto-cleaned on PJAX!)
        var aside = document.createElement('aside');
        aside.id = 'desktop-toc';
        aside.className = 'toc-desktop';
        aside.setAttribute('aria-label', '文章目录');
        aside.innerHTML = '<p class="toc-desktop-title">✦ 目录导航</p>';
        aside.appendChild(makeTocList(null));
        feed.appendChild(aside);

        // Mobile slide-up TOC sheet (synced with scroll-spy)
        ensureTocSheet();
        tocSheetBody.innerHTML = '';
        tocSheetBody.appendChild(makeTocList(closeTocSheet));
      }
    }

    // Floating mini-FAB stack inside #pjax-stage (mobile TOC drawer + comment quick-jump)
    if (feed && (hasToc || commentsCard) && !document.getElementById('article-fabs')) {
      var fabs = document.createElement('div');
      fabs.id = 'article-fabs';
      fabs.className = 'article-fabs';
      if (hasToc) {
        var tocBtn = document.createElement('button');
        tocBtn.type = 'button';
        tocBtn.className = 'fab-btn fab-btn-toc';
        tocBtn.title = '展开文章目录';
        tocBtn.setAttribute('aria-label', '展开文章目录');
        tocBtn.textContent = '☰';
        tocBtn.addEventListener('click', openTocSheet);
        fabs.appendChild(tocBtn);
      }
      if (commentsCard) {
        var cmtBtn = document.createElement('button');
        cmtBtn.type = 'button';
        cmtBtn.className = 'fab-btn fab-btn-comment';
        cmtBtn.title = '直达评论区';
        cmtBtn.setAttribute('aria-label', '直达评论区');
        cmtBtn.textContent = '💬';
        cmtBtn.addEventListener('click', function () {
          commentsCard.scrollIntoView({ behavior: reducedMotion ? 'auto' : 'smooth' });
        });
        fabs.appendChild(cmtBtn);
      }
      feed.appendChild(fabs);
    }
  }

  function initArchiveYears() {
    var list = document.querySelector('.archive-timeline');
    if (!list || list.dataset.yearsGrouped) return;
    list.dataset.yearsGrouped = '1';
    var items = Array.prototype.slice.call(list.querySelectorAll('.archive-item'));
    if (!items.length) return;
    var counts = {};
    var years = [];
    items.forEach(function (li) {
      var t = li.querySelector('.archive-date');
      var m = t ? (t.textContent || '').trim().match(/^(\d{4})/) : null;
      var y = m ? m[1] : '';
      years.push(y);
      if (y) counts[y] = (counts[y] || 0) + 1;
    });
    var seen = {};
    items.forEach(function (li, idx) {
      var y = years[idx];
      if (!y || seen[y]) return;
      seen[y] = true;
      var hdr = document.createElement('li');
      hdr.className = 'archive-year';
      hdr.innerHTML = '<span>✦ ' + y + ' 年</span><small>' + counts[y] + ' 篇</small>';
      list.insertBefore(hdr, li);
    });
  }

  function esc(s) {
    return String(s || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function highlightText(raw, q) {
    var text = String(raw || '');
    if (!q) return esc(text);
    var low = text.toLowerCase();
    var needle = q.toLowerCase();
    var out = '';
    var pos = 0;
    var idx;
    while ((idx = low.indexOf(needle, pos)) !== -1) {
      out += esc(text.slice(pos, idx)) + '<mark class="search-hl">' + esc(text.slice(idx, idx + needle.length)) + '</mark>';
      pos = idx + needle.length;
    }
    out += esc(text.slice(pos));
    return out;
  }

  function getSearchIndex(cb) {
    if (searchIndexCache) { cb(searchIndexCache); return; }
    fetch('/search-index.json')
      .then(function (r) { return r.json(); })
      .then(function (data) {
        searchIndexCache = Array.isArray(data) ? data : [];
        cb(searchIndexCache);
      })
      .catch(function () {});
  }

  function filterSearchPosts(list, q) {
    var needle = q.toLowerCase();
    return list.filter(function (p) {
      return (
        (p.title || '').toLowerCase().indexOf(needle) !== -1 ||
        (p.summary || '').toLowerCase().indexOf(needle) !== -1 ||
        (p.category || '').toLowerCase().indexOf(needle) !== -1 ||
        (p.tags || '').toLowerCase().indexOf(needle) !== -1
      );
    });
  }

  function topSearchKeywords(list, limit) {
    var freq = {};
    list.forEach(function (p) {
      (p.tags || '').split(',').forEach(function (raw) {
        var t = raw.trim();
        if (t) freq[t] = (freq[t] || 0) + 1;
      });
      if (p.category) freq[p.category] = (freq[p.category] || 0) + 1;
    });
    return Object.keys(freq).sort(function (a, b) { return freq[b] - freq[a]; }).slice(0, limit || 10);
  }

  /* Global Instant Command Search Modal (Ctrl/Cmd+K & /) */
  function ensureCmdSearch() {
    if (cmdEl) return;
    var wrap = document.createElement('div');
    wrap.id = 'cmd-search';
    wrap.className = 'cmd-modal';
    wrap.setAttribute('role', 'dialog');
    wrap.setAttribute('aria-modal', 'true');
    wrap.setAttribute('aria-label', '全站快捷搜索');
    wrap.innerHTML =
      '<div class="cmd-panel">' +
      '<div class="cmd-head">' +
      '<span class="cmd-icon" aria-hidden="true"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="M20 20 L16.2 16.2"/></svg></span>' +
      '<input id="cmd-input" class="cmd-input" type="search" placeholder="快速搜索文章、标签、分类..." autocomplete="off">' +
      '<button type="button" class="cmd-esc">ESC</button>' +
      '</div>' +
      '<div id="cmd-body" class="cmd-body"><div class="cmd-empty">正在加载索引…</div></div>' +
      '<div class="cmd-foot"><span><kbd>↑</kbd> <kbd>↓</kbd> 选择 · <kbd>Enter</kbd> 直达 · <kbd>ESC</kbd> 关闭</span><span>✦ 即时检索</span></div>' +
      '</div>';
    document.body.appendChild(wrap);
    cmdEl = wrap;
    cmdInput = wrap.querySelector('#cmd-input');
    cmdBody = wrap.querySelector('#cmd-body');
    wrap.querySelector('.cmd-esc').addEventListener('click', closeCmdSearch);
    wrap.addEventListener('click', function (e) {
      if (e.target === wrap) closeCmdSearch();
    });
    cmdInput.addEventListener('input', function () {
      renderCmdSearch(cmdInput.value.trim());
    });
  }

  function updateCmdActive() {
    if (!cmdBody) return;
    var items = cmdBody.querySelectorAll('.cmd-item');
    items.forEach(function (el, idx) {
      var on = idx === cmdActiveIdx;
      el.classList.toggle('is-active', on);
      if (on && el.scrollIntoView) {
        try { el.scrollIntoView({ block: 'nearest' }); } catch (_) {}
      }
    });
  }

  function jumpCmdIndex(idx) {
    var p = cmdHits[idx];
    if (!p || !p.slug) return;
    closeCmdSearch();
    smoothNavigate(new URL('/post/' + p.slug + '/', window.location.origin), true);
  }

  function renderCmdSearch(q) {
    getSearchIndex(function (list) {
      if (!cmdBody) return;
      var hits = q ? filterSearchPosts(list, q) : list.slice(0, 6);
      cmdHits = hits.slice(0, 12);
      cmdActiveIdx = 0;

      var html = '';
      if (!q) {
        var top = topSearchKeywords(list, 8);
        if (top.length) {
          html += '<div class="cmd-section-label">✦ 热门标签快捷搜</div><div class="cmd-chips">' +
            top.map(function (k) {
              return '<button type="button" class="search-chip" data-cmd-q="' + esc(k) + '">#' + esc(k) + '</button>';
            }).join('') + '</div>';
        }
        html += '<div class="cmd-section-label">✦ 最新发布</div>';
      } else {
        html += '<div class="cmd-section-label">✦ 找到 ' + hits.length + ' 篇相关笔记</div>';
      }

      if (!cmdHits.length) {
        html += '<div class="cmd-empty">没有找到与「' + esc(q) + '」相关的内容呢，换个词试试吧～</div>';
      } else {
        html += '<div class="cmd-list">' + cmdHits.map(function (p, idx) {
          var sub = p.summary || (p.category ? ('✦ ' + p.category) : '');
          return (
            '<button type="button" class="cmd-item' + (idx === 0 ? ' is-active' : '') + '" data-cmd-idx="' + idx + '">' +
            '<div class="cmd-item-top"><span class="cmd-item-title">' + highlightText(p.title, q) + '</span>' +
            '<span class="cmd-item-date">' + esc(p.date) + '</span></div>' +
            (sub ? '<span class="cmd-item-sub">' + highlightText(sub, q) + '</span>' : '') +
            '</button>'
          );
        }).join('') + '</div>';
      }

      cmdBody.innerHTML = html;
      cmdBody.querySelectorAll('[data-cmd-q]').forEach(function (chip) {
        chip.addEventListener('click', function () {
          var kw = chip.getAttribute('data-cmd-q') || '';
          cmdInput.value = kw;
          cmdInput.focus();
          renderCmdSearch(kw);
        });
      });
      cmdBody.querySelectorAll('[data-cmd-idx]').forEach(function (btn) {
        btn.addEventListener('mouseenter', function () {
          cmdActiveIdx = parseInt(btn.getAttribute('data-cmd-idx') || '0', 10);
          updateCmdActive();
        });
        btn.addEventListener('click', function () {
          jumpCmdIndex(parseInt(btn.getAttribute('data-cmd-idx') || '0', 10));
        });
      });
    });
  }

  function openCmdSearch() {
    ensureCmdSearch();
    closeLightbox();
    closeTocSheet();
    cmdEl.classList.add('is-open');
    syncBodyLock();
    renderCmdSearch(cmdInput.value.trim());
    setTimeout(function () { if (cmdInput) { cmdInput.focus(); cmdInput.select(); } }, 20);
  }

  function closeCmdSearch() {
    if (!cmdEl || !cmdEl.classList.contains('is-open')) return;
    cmdEl.classList.remove('is-open');
    syncBodyLock();
  }

  var quickSearchBtn = document.getElementById('quick-search-btn');
  if (quickSearchBtn) {
    quickSearchBtn.addEventListener('click', openCmdSearch);
  }

  function initSearch() {
    var searchInput = document.getElementById('search-input');
    var resultsBox = document.getElementById('search-results');
    var metaBox = document.getElementById('search-meta');
    var searchForm = document.getElementById('search-form');
    if (!searchInput || !resultsBox) return;

    function renderSuggestions(list) {
      if (!metaBox) return;
      var top = topSearchKeywords(list, 10);
      if (!top.length) {
        metaBox.innerHTML = '';
        return;
      }
      metaBox.innerHTML =
        '<div class="search-suggest">' +
        '<p class="search-suggest-title">✦ 热门关键词快捷搜</p>' +
        '<div class="search-chips">' +
        top.map(function (k) {
          return '<button type="button" class="search-chip" data-q="' + esc(k) + '">#' + esc(k) + '</button>';
        }).join('') +
        '</div></div>';
      metaBox.querySelectorAll('.search-chip').forEach(function (btn) {
        btn.addEventListener('click', function () {
          var kw = btn.getAttribute('data-q') || '';
          searchInput.value = kw;
          history.replaceState({}, '', '/search/?q=' + encodeURIComponent(kw));
          runSearch(kw);
        });
      });
    }

    function renderHits(list, q) {
      if (!q) {
        resultsBox.innerHTML = '';
        renderSuggestions(list);
        recalcMetrics();
        return;
      }
      var hits = filterSearchPosts(list, q);
      if (metaBox) {
        metaBox.innerHTML = '<span class="search-count">✦ 找到 ' + hits.length + ' 篇相关笔记</span>';
      }
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
        var hasCover = !!p.cover;
        var ribbonHtml = hasCover ? '' : '<div class="ribbon-corner" aria-hidden="true"><span>★</span></div>';
        var coverHtml = hasCover
          ? '<a class="post-cover-link" href="/post/' + esc(p.slug) + '/"><img class="post-cover" src="' + esc(p.cover) + '" alt="' + esc(p.title) + '" loading="lazy" decoding="async"></a>'
          : '';
        var catHtml = p.category
          ? '<a class="cat-badge" href="/category/' + encodeURIComponent(p.category) + '/">✦ ' + esc(p.category) + '</a>'
          : '';
        return (
          '<article class="post-card' + (hasCover ? ' has-cover' : '') + '">' +
          ribbonHtml +
          coverHtml +
          '<div class="post-body">' +
          '<div class="post-meta">' + catHtml + '<time>' + esc(p.date) + '</time></div>' +
          '<h2 class="post-card-title"><a href="/post/' + esc(p.slug) + '/">' + highlightText(p.title, q) + '</a></h2>' +
          '<p class="post-summary">' + highlightText(p.summary, q) + '</p>' +
          '<div class="post-card-foot"><div class="tag-row">' + tagsHtml + '</div>' +
          '<a class="read-more" href="/post/' + esc(p.slug) + '/">阅读全文 <span aria-hidden="true">&rarr;</span></a></div>' +
          '</div></article>'
        );
      }).join('');
      enhanceImages();
      recalcMetrics();
    }

    function runSearch(q) {
      getSearchIndex(function (list) { renderHits(list, q); });
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
    if (initQ) {
      if (!searchInput.value) searchInput.value = initQ;
      runSearch(initQ);
    } else {
      runSearch('');
    }
  }

  function syncCatBarFade() {
    document.querySelectorAll('.cat-bar').forEach(function (bar) {
      var scrollable = bar.scrollWidth > bar.clientWidth + 4;
      bar.classList.toggle('is-scrollable', scrollable);
      if (scrollable) {
        var atEnd = bar.scrollLeft + bar.clientWidth >= bar.scrollWidth - 4;
        bar.classList.toggle('is-scroll-end', atEnd);
      } else {
        bar.classList.remove('is-scroll-end');
      }
    });
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
    document.querySelectorAll('.cat-bar').forEach(function (bar) {
      if (!bar.dataset.fadeBound) {
        bar.dataset.fadeBound = '1';
        bar.addEventListener('scroll', syncCatBarFade, { passive: true });
      }
    });
    syncCatBarFade();
  }

  function initComments() {
    var card = document.getElementById('comments-card');
    var mount = document.getElementById('giscus-mount');
    if (!card || !mount || card.dataset.giscusInit) return;
    var repo = (card.getAttribute('data-repo') || '').trim();
    var repoId = (card.getAttribute('data-repo-id') || '').trim();
    var cat = (card.getAttribute('data-category') || '').trim();
    var catId = (card.getAttribute('data-category-id') || '').trim();
    if (!repo || !repoId || !catId) {
      mount.innerHTML = '<p class="comments-loading">评论区尚未填写完整的 Giscus 仓库与分类 ID（请在后台「⚙️ 站点设置」补全）。</p>';
      return;
    }
    card.dataset.giscusInit = '1';

    function loadGiscus() {
      if (card.dataset.giscusLoaded) return;
      card.dataset.giscusLoaded = '1';
      mount.innerHTML = '';
      var sc = document.createElement('script');
      sc.src = 'https://giscus.app/client.js';
      sc.async = true;
      sc.crossOrigin = 'anonymous';
      sc.setAttribute('data-repo', repo);
      sc.setAttribute('data-repo-id', repoId);
      sc.setAttribute('data-category', cat || 'General');
      sc.setAttribute('data-category-id', catId);
      sc.setAttribute('data-mapping', 'pathname');
      sc.setAttribute('data-strict', '0');
      sc.setAttribute('data-reactions-enabled', '1');
      sc.setAttribute('data-emit-metadata', '0');
      sc.setAttribute('data-input-position', 'top');
      sc.setAttribute('data-theme', giscusThemeFor(root.getAttribute('data-theme')));
      sc.setAttribute('data-lang', 'zh-CN');
      sc.setAttribute('data-loading', 'lazy');
      mount.appendChild(sc);
    }

    if ('IntersectionObserver' in window) {
      var io = new IntersectionObserver(function (entries) {
        if (entries.some(function (en) { return en.isIntersecting; })) {
          io.disconnect();
          loadGiscus();
        }
      }, { rootMargin: '260px 0px' });
      io.observe(card);
    } else {
      loadGiscus();
    }
  }

  function isSafeFrontUrl(u) {
    var s = String(u || '').trim();
    return s.indexOf('/') === 0 || /^https?:\/\//i.test(s);
  }

  /* Curated Illustration Gallery (/gallery/) */
  function initGallery() {
    var grid = document.getElementById('gallery-grid');
    var bar = document.getElementById('gallery-filter-bar');
    if (!grid || grid.dataset.galInit) return;
    grid.dataset.galInit = '1';

    fetch('/gallery.json')
      .then(function (r) { return r.json(); })
      .then(function (data) {
        var all = (Array.isArray(data) ? data : []).filter(function (it) {
          return it && isSafeFrontUrl(it.url);
        });
        if (!all.length) {
          if (bar) bar.innerHTML = '';
          grid.innerHTML = '<div class="empty-state">画廊里还没有放进精选作品哦～ 博主可以在创作后台「🖼️ 精选画廊」亲自挑选美图放进来 ✦</div>';
          recalcMetrics();
          return;
        }

        var activeTag = '';
        var tagCounts = {};
        all.forEach(function (it) {
          var t = String(it.tag || '').trim();
          if (t) tagCounts[t] = (tagCounts[t] || 0) + 1;
        });
        var tagList = Object.keys(tagCounts);

        function renderBar() {
          if (!bar) return;
          if (!tagList.length) {
            bar.innerHTML = '<span class="cat-pill is-active">✦ 全部精选 <span class="cat-pill-cnt">' + all.length + '</span></span>';
            return;
          }
          var html = '<button type="button" class="cat-pill' + (!activeTag ? ' is-active' : '') + '" data-gal-tag="">✦ 全部 <span class="cat-pill-cnt">' + all.length + '</span></button>';
          tagList.forEach(function (t) {
            html += '<button type="button" class="cat-pill' + (activeTag === t ? ' is-active' : '') + '" data-gal-tag="' + esc(t) + '">#' + esc(t) + ' <span class="cat-pill-cnt">' + tagCounts[t] + '</span></button>';
          });
          bar.innerHTML = html;
          bar.querySelectorAll('[data-gal-tag]').forEach(function (btn) {
            btn.addEventListener('click', function () {
              activeTag = btn.getAttribute('data-gal-tag') || '';
              renderBar();
              renderCards();
            });
          });
          syncCatBarFade();
        }

        function renderCards() {
          var shown = activeTag
            ? all.filter(function (it) { return String(it.tag || '').trim() === activeTag; })
            : all;
          if (!shown.length) {
            grid.innerHTML = '<div class="empty-state">这个分类下暂时没有精选作品～</div>';
            recalcMetrics();
            return;
          }
          var lbItems = shown.map(function (it) {
            var cap = String(it.title || '').trim();
            var note = String(it.note || '').trim();
            return {
              src: it.url,
              orig: extractOrigUrl(it.url),
              alt: cap && note ? (cap + ' · ' + note) : (cap || note || '精选作品')
            };
          });
          grid.innerHTML = shown.map(function (it, idx) {
            var title = String(it.title || '').trim();
            var tag = String(it.tag || '').trim();
            var note = String(it.note || '').trim();
            var hasInfo = !!(title || tag || note);
            var infoHtml = hasInfo
              ? '<div class="gal-info">' +
                ((title || tag)
                  ? '<div class="gal-top">' + (title ? '<p class="gal-title">' + esc(title) + '</p>' : '<span></span>') + (tag ? '<span class="gal-tag">#' + esc(tag) + '</span>' : '') + '</div>'
                  : '') +
                (note ? '<p class="gal-note">' + esc(note) + '</p>' : '') +
                '</div>'
              : '';
            return (
              '<figure class="gal-card" data-gal-idx="' + idx + '">' +
              '<img class="gal-img" src="' + esc(it.url) + '" alt="' + esc(title || '精选作品') + '" loading="lazy" decoding="async">' +
              infoHtml +
              '</figure>'
            );
          }).join('');

          grid.querySelectorAll('.gal-card').forEach(function (card) {
            card.addEventListener('click', function () {
              var i = parseInt(card.getAttribute('data-gal-idx') || '0', 10);
              openLightbox(lbItems, i);
            });
          });
          grid.querySelectorAll('.gal-img').forEach(function (im) {
            if (im.complete && im.naturalWidth > 0) return;
            im.classList.add('img-fade');
            var done = function () { im.classList.add('is-loaded'); recalcMetrics(); };
            im.addEventListener('load', done, { once: true });
            im.addEventListener('error', done, { once: true });
          });
          recalcMetrics();
        }

        renderBar();
        renderCards();
      })
      .catch(function () {
        grid.innerHTML = '<div class="empty-state">画廊加载失败，请稍后刷新重试～</div>';
      });
  }

  /* About Me & Friends Wall (/about/) */
  function initAbout() {
    var bioEl = document.getElementById('about-bio');
    var friendsGrid = document.getElementById('friends-grid');
    if (!bioEl || !friendsGrid || bioEl.dataset.aboutInit) return;
    bioEl.dataset.aboutInit = '1';

    fetch('/about.json')
      .then(function (r) { return r.json(); })
      .then(function (data) {
        var cfg = (data && typeof data === 'object') ? data : {};
        var bio = String(cfg.bio || '').trim();
        if (bio) {
          bioEl.innerHTML = bio.split(/\n+/).map(function (line) {
            return line.trim() ? ('<p>' + esc(line.trim()) + '</p>') : '';
          }).join('');
        }
        var tagsEl = document.getElementById('about-tags');
        if (tagsEl) {
          var tags = Array.isArray(cfg.tags) ? cfg.tags : [];
          tagsEl.innerHTML = tags
            .map(function (t) { return String(t || '').trim(); })
            .filter(Boolean)
            .map(function (t) { return '<span class="tag-chip">#' + esc(t) + '</span>'; })
            .join('');
        }
        var socEl = document.getElementById('about-socials');
        if (socEl) {
          var socials = (Array.isArray(cfg.socials) ? cfg.socials : []).filter(function (s) {
            return s && s.label && isSafeFrontUrl(s.url);
          });
          socEl.innerHTML = socials.map(function (s) {
            return '<a class="social-pill" href="' + esc(s.url) + '" target="_blank" rel="noopener noreferrer">✦ ' + esc(s.label) + ' ↗</a>';
          }).join('');
        }
        var friends = (Array.isArray(cfg.friends) ? cfg.friends : []).filter(function (f) {
          return f && f.name && isSafeFrontUrl(f.url);
        });
        var cntEl = document.getElementById('friends-count');
        if (cntEl) cntEl.textContent = friends.length ? (friends.length + ' 位小伙伴') : '欢迎交换友链';
        if (!friends.length) {
          friendsGrid.innerHTML = '<div class="empty-state">友链星海等待点亮中～ 可在创作后台「🎀 关于与友链」添加小伙伴的站点 ✦</div>';
        } else {
          friendsGrid.innerHTML = friends.map(function (f) {
            var av = isSafeFrontUrl(f.avatar) ? f.avatar : '/static/avatar.webp?v=3&orig=/static/avatar.jpg';
            return (
              '<a class="friend-card" href="' + esc(f.url) + '" target="_blank" rel="noopener noreferrer">' +
              '<img class="friend-avatar" src="' + esc(av) + '" alt="' + esc(f.name) + '" loading="lazy" decoding="async">' +
              '<div class="friend-info">' +
              '<p class="friend-name">' + esc(f.name) + '</p>' +
              '<p class="friend-desc">' + esc(f.desc || f.url) + '</p>' +
              '</div></a>'
            );
          }).join('');
        }
        recalcMetrics();
      })
      .catch(function () {
        friendsGrid.innerHTML = '<div class="empty-state">暂时未能读取关于与友链信息～</div>';
      });
  }

  /* PJAX Continuous Mini BGM Player (mounted outside #pjax-stage; never auto-plays!) */
  var bgm = { el: null, audio: null, list: [], idx: 0, loopOne: false, playing: false, inited: false };

  function pauseBgm() {
    if (bgm.audio && !bgm.audio.paused) {
      try { bgm.audio.pause(); } catch (_) {}
    }
  }

  function fmtAudioTime(sec) {
    if (!sec || !isFinite(sec)) return '0:00';
    var m = Math.floor(sec / 60);
    var s = Math.floor(sec % 60);
    return m + ':' + (s < 10 ? '0' : '') + s;
  }

  function initBgmPlayer() {
    if (bgm.inited) return;
    bgm.inited = true;

    fetch('/bgm.json')
      .then(function (r) { return r.json(); })
      .then(function (data) {
        var tracks = (Array.isArray(data) ? data : []).filter(function (t) {
          return t && isSafeFrontUrl(t.url);
        });
        if (!tracks.length) return;
        bgm.list = tracks;

        var dock = document.createElement('div');
        dock.id = 'bgm-dock';
        dock.className = 'bgm-dock';
        dock.innerHTML =
          '<button type="button" class="bgm-disc" title="星梦唱片机 · 点击展开/收起" aria-label="展开音乐播放器"><span class="bgm-disc-glyph">♪</span></button>' +
          '<div class="bgm-panel" role="region" aria-label="站内音乐播放器">' +
          '<div class="bgm-head"><div class="bgm-meta"><p class="bgm-title"></p><p class="bgm-artist"></p></div><button type="button" class="bgm-close" aria-label="收起">✕</button></div>' +
          '<div class="bgm-bar" title="点击跳转播放进度"><div class="bgm-bar-fill"></div></div>' +
          '<div class="bgm-ctrl-row">' +
          '<div class="bgm-btns">' +
          '<button type="button" class="bgm-btn" data-bgm="prev" title="上一首">⏮</button>' +
          '<button type="button" class="bgm-btn bgm-btn-play" data-bgm="play" title="播放 / 暂停">▶</button>' +
          '<button type="button" class="bgm-btn" data-bgm="next" title="下一首">⏭</button>' +
          '<button type="button" class="bgm-btn" data-bgm="loop" title="切换列表循环 / 单曲循环">🔁</button>' +
          '</div>' +
          '<span class="bgm-time">0:00 / 0:00</span>' +
          '</div></div>';
        document.body.appendChild(dock);

        var audio = new Audio();
        audio.preload = 'none';
        bgm.el = dock;
        bgm.audio = audio;

        var discBtn = dock.querySelector('.bgm-disc');
        var closeBtn = dock.querySelector('.bgm-close');
        var titleEl = dock.querySelector('.bgm-title');
        var artistEl = dock.querySelector('.bgm-artist');
        var barEl = dock.querySelector('.bgm-bar');
        var fillEl = dock.querySelector('.bgm-bar-fill');
        var timeEl = dock.querySelector('.bgm-time');
        var playBtn = dock.querySelector('[data-bgm="play"]');
        var prevBtn = dock.querySelector('[data-bgm="prev"]');
        var nextBtn = dock.querySelector('[data-bgm="next"]');
        var loopBtn = dock.querySelector('[data-bgm="loop"]');

        function loadTrack(i, autoPlay) {
          bgm.idx = (i + bgm.list.length) % bgm.list.length;
          var tr = bgm.list[bgm.idx];
          titleEl.textContent = tr.title || ('曲目 ' + (bgm.idx + 1));
          artistEl.textContent = (tr.artist || 'BGM') + (bgm.list.length > 1 ? (' · ' + (bgm.idx + 1) + '/' + bgm.list.length) : '');
          fillEl.style.width = '0%';
          timeEl.textContent = '0:00 / 0:00';
          audio.src = tr.url;
          if (autoPlay) {
            audio.play().catch(function () { showToast('请再点一下播放按钮启动音乐 ♪'); });
          }
        }

        if (bgm.list.length <= 1) {
          prevBtn.style.display = 'none';
          nextBtn.style.display = 'none';
        }

        function syncPlayState() {
          bgm.playing = !audio.paused && !audio.ended;
          dock.classList.toggle('is-playing', bgm.playing);
          playBtn.textContent = bgm.playing ? '⏸' : '▶';
        }

        discBtn.addEventListener('click', function () {
          dock.classList.toggle('is-open');
        });
        closeBtn.addEventListener('click', function () {
          dock.classList.remove('is-open');
        });
        playBtn.addEventListener('click', function () {
          if (!audio.src) loadTrack(bgm.idx, true);
          else if (audio.paused) audio.play().catch(function () {});
          else audio.pause();
        });
        prevBtn.addEventListener('click', function () { loadTrack(bgm.idx - 1, true); });
        nextBtn.addEventListener('click', function () { loadTrack(bgm.idx + 1, true); });
        loopBtn.addEventListener('click', function () {
          bgm.loopOne = !bgm.loopOne;
          loopBtn.classList.toggle('is-active', bgm.loopOne);
          loopBtn.textContent = bgm.loopOne ? '🔂' : '🔁';
          showToast(bgm.loopOne ? '已切换为单曲循环 🔂' : '已切换为列表循环 🔁');
        });
        barEl.addEventListener('click', function (e) {
          if (!audio.duration || !isFinite(audio.duration)) return;
          var rect = barEl.getBoundingClientRect();
          var ratio = Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width));
          audio.currentTime = ratio * audio.duration;
        });

        audio.addEventListener('play', function () {
          // Pause any playing post video so audio streams never clash
          document.querySelectorAll('video').forEach(function (v) {
            if (!v.paused) { try { v.pause(); } catch (_) {} }
          });
          syncPlayState();
        });
        audio.addEventListener('pause', syncPlayState);
        audio.addEventListener('timeupdate', function () {
          var dur = audio.duration || 0;
          var cur = audio.currentTime || 0;
          if (dur > 0 && isFinite(dur)) {
            fillEl.style.width = ((cur / dur) * 100).toFixed(2) + '%';
            timeEl.textContent = fmtAudioTime(cur) + ' / ' + fmtAudioTime(dur);
          }
        });
        audio.addEventListener('ended', function () {
          if (bgm.loopOne || bgm.list.length === 1) {
            audio.currentTime = 0;
            audio.play().catch(function () {});
          } else {
            loadTrack(bgm.idx + 1, true);
          }
        });
        audio.addEventListener('error', function () {
          syncPlayState();
          showToast('当前音频无法加载，请检查链接');
        });

        loadTrack(0, false);
      })
      .catch(function () {});
  }

  /* Zero-Tracker Article Views & Heart Likes (/api/stats/*) */
  function initArticleStats() {
    var art = document.querySelector('article[data-post-slug]');
    if (!art || art.dataset.statsInit) return;
    art.dataset.statsInit = '1';
    var slug = (art.getAttribute('data-post-slug') || '').trim();
    if (!slug) return;

    var viewsWrap = document.getElementById('post-views-wrap');
    var viewsNum = document.getElementById('post-views-num');
    var likeBtn = document.getElementById('like-post-btn');
    var likeNum = document.getElementById('like-post-num');
    var isDraft = !!art.querySelector('.draft-preview-banner');
    var viewKey = 'asmblog-viewed-' + slug;
    var likeKey = 'asmblog-liked-' + slug;

    function isLikedLocal() {
      try { return localStorage.getItem(likeKey) === '1'; } catch (_) { return false; }
    }
    function setLikedUI(liked) {
      if (!likeBtn) return;
      likeBtn.classList.toggle('is-liked', liked);
      likeBtn.setAttribute('aria-pressed', liked ? 'true' : 'false');
      var heart = likeBtn.querySelector('.like-heart');
      var lbl = likeBtn.querySelector('.like-label');
      if (heart) heart.textContent = liked ? '♥' : '♡';
      if (lbl) lbl.textContent = liked ? '已喜欢' : '喜欢';
    }
    function applyCounts(d) {
      if (!d || typeof d !== 'object') return;
      if (viewsNum && typeof d.views === 'number') {
        viewsNum.textContent = String(d.views);
        if (viewsWrap) viewsWrap.classList.remove('hidden');
      }
      if (likeNum && typeof d.likes === 'number') {
        likeNum.textContent = String(d.likes);
        if (likeBtn && !isDraft) likeBtn.classList.remove('hidden');
      }
    }

    setLikedUI(isLikedLocal());

    var alreadyViewed = false;
    try { alreadyViewed = sessionStorage.getItem(viewKey) === '1'; } catch (_) {}

    var req = (isDraft || alreadyViewed)
      ? fetch('/api/stats/' + encodeURIComponent(slug), { cache: 'no-store' })
      : fetch('/api/stats/view', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ slug: slug })
        });

    req
      .then(function (r) {
        if (!r.ok) throw new Error('stats unavailable');
        return r.json();
      })
      .then(function (d) {
        if (!isDraft && !alreadyViewed) {
          try { sessionStorage.setItem(viewKey, '1'); } catch (_) {}
        }
        applyCounts(d);
      })
      .catch(function () {
        /* Gracefully stay hidden on static-only hosting */
      });

    if (likeBtn && !isDraft) {
      var busy = false;
      likeBtn.addEventListener('click', function () {
        if (busy) return;
        if (isLikedLocal()) {
          likeBtn.classList.remove('is-popping');
          void likeBtn.offsetWidth;
          likeBtn.classList.add('is-popping');
          showToast('已经给这篇文章比过心啦 ♥');
          return;
        }
        busy = true;
        fetch('/api/stats/like', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ slug: slug })
        })
          .then(function (r) {
            if (r.status === 429) {
              showToast('点赞太热情啦，稍等片刻再试哦～');
              return null;
            }
            if (!r.ok) throw new Error('like failed');
            return r.json();
          })
          .then(function (d) {
            if (!d) return;
            try { localStorage.setItem(likeKey, '1'); } catch (_) {}
            setLikedUI(true);
            applyCounts(d);
            likeBtn.classList.remove('is-popping');
            void likeBtn.offsetWidth;
            likeBtn.classList.add('is-popping');
            showToast('感谢你的喜欢 ♥');
          })
          .catch(function () {
            showToast('点赞请求失败，请稍后重试');
          })
          .finally(function () { busy = false; });
      });
    }
  }

  /* Moments / 碎碎念 Timeline (/moments/) */
  function formatMomentText(raw) {
    var s = String(raw || '');
    var re = /(https?:\/\/[^\s<>"'）)，。！？；：、\]》】]+)/gi;
    var out = '';
    var last = 0;
    var m;
    while ((m = re.exec(s)) !== null) {
      if (m.index > last) out += esc(s.slice(last, m.index));
      var u = m[0];
      var trail = '';
      while (/[.,;:!?]$/.test(u)) {
        trail = u.slice(-1) + trail;
        u = u.slice(0, -1);
      }
      if (/^https?:\/\/\S+/i.test(u)) {
        var su = esc(u);
        out += '<a href="' + su + '" target="_blank" rel="noopener noreferrer">' + su + '</a>' + esc(trail);
      } else {
        out += esc(m[0]);
      }
      last = re.lastIndex;
    }
    if (last < s.length) out += esc(s.slice(last));
    return out.replace(/\n/g, '<br>');
  }

  function initMoments() {
    var feed = document.getElementById('moments-feed');
    var bar = document.getElementById('moments-filter-bar');
    var moreWrap = document.getElementById('moments-more-wrap');
    if (!feed || feed.dataset.momInit) return;
    feed.dataset.momInit = '1';

    var author = feed.getAttribute('data-author') || '博主';
    var avatar = feed.getAttribute('data-avatar') || '/static/avatar.webp?v=3&orig=/static/avatar.jpg';
    if (!isSafeFrontUrl(avatar)) avatar = '/static/avatar.webp?v=3&orig=/static/avatar.jpg';

    fetch('/moments.json')
      .then(function (r) { return r.json(); })
      .then(function (data) {
        var all = (Array.isArray(data) ? data : []).filter(function (m) {
          if (!m || typeof m !== 'object') return false;
          var hasTxt = String(m.text || '').trim().length > 0;
          var imgs = Array.isArray(m.images) ? m.images.filter(isSafeFrontUrl) : [];
          return hasTxt || imgs.length > 0;
        });
        // Sort pinned moments first while preserving relative chronological order
        all = all.filter(function (m) { return !!m.pinned; }).concat(all.filter(function (m) { return !m.pinned; }));

        if (!all.length) {
          if (bar) bar.innerHTML = '';
          if (moreWrap) moreWrap.innerHTML = '';
          feed.innerHTML = '<div class="empty-state">碎碎念还是空的～ 博主可以在创作后台「💬 碎碎念」随手发第一条动态 ✦</div>';
          recalcMetrics();
          return;
        }

        var activeMood = '';
        var limit = 15;
        var moodCounts = {};
        all.forEach(function (m) {
          var md = String(m.mood || '').trim();
          if (md) moodCounts[md] = (moodCounts[md] || 0) + 1;
        });
        var moods = Object.keys(moodCounts);

        function renderBar() {
          if (!bar) return;
          if (!moods.length) { bar.innerHTML = ''; return; }
          var html = '<button type="button" class="cat-pill' + (!activeMood ? ' is-active' : '') + '" data-mom-mood="">全部 <span class="cat-count">' + all.length + '</span></button>';
          moods.forEach(function (md) {
            html += '<button type="button" class="cat-pill' + (activeMood === md ? ' is-active' : '') + '" data-mom-mood="' + esc(md) + '">' + esc(md) + ' <span class="cat-count">' + moodCounts[md] + '</span></button>';
          });
          bar.innerHTML = html;
          bar.querySelectorAll('[data-mom-mood]').forEach(function (btn) {
            btn.addEventListener('click', function () {
              activeMood = btn.getAttribute('data-mom-mood') || '';
              limit = 15;
              renderBar();
              renderFeed();
            });
          });
        }

        function renderFeed() {
          var filtered = activeMood
            ? all.filter(function (m) { return String(m.mood || '').trim() === activeMood; })
            : all;
          var shown = filtered.slice(0, limit);
          feed.innerHTML = shown.map(function (m, idx) {
            var imgs = (Array.isArray(m.images) ? m.images : []).filter(isSafeFrontUrl).slice(0, 9);
            var gridCls = imgs.length === 1 ? 'photos-1' : ((imgs.length === 2 || imgs.length === 4) ? 'photos-2' : 'photos-3');
            var photosHtml = imgs.length
              ? '<div class="moment-photos ' + gridCls + '">' + imgs.map(function (u, pi) {
                  return '<button type="button" class="moment-photo-item" data-midx="' + idx + '" data-pidx="' + pi + '" aria-label="放大查看图片">' +
                    '<img class="moment-photo-img" src="' + esc(u) + '" alt="" loading="lazy" decoding="async">' +
                    '</button>';
                }).join('') + '</div>'
              : '';
            var pinHtml = m.pinned ? '<span class="pin-badge">📌 置顶</span>' : '';
            var moodHtml = m.mood ? '<span class="moment-mood">' + esc(m.mood) + '</span>' : '';
            var txtHtml = String(m.text || '').trim() ? '<p class="moment-text">' + formatMomentText(m.text) + '</p>' : '';
            return (
              '<article class="moment-card">' +
                '<div class="moment-head">' +
                  '<img class="moment-avatar" src="' + esc(avatar) + '" alt="' + esc(author) + '" loading="lazy" decoding="async">' +
                  '<div class="moment-meta">' +
                    '<div class="moment-author-row">' +
                      '<span class="moment-author">' + esc(author) + '</span>' +
                      pinHtml + moodHtml +
                    '</div>' +
                    '<div class="moment-time">' + esc(m.date || '') + '</div>' +
                  '</div>' +
                '</div>' +
                txtHtml + photosHtml +
              '</article>'
            );
          }).join('');

          feed.querySelectorAll('.moment-photo-item').forEach(function (btn) {
            btn.addEventListener('click', function () {
              var mi = parseInt(btn.getAttribute('data-midx') || '0', 10);
              var pi = parseInt(btn.getAttribute('data-pidx') || '0', 10);
              var m = shown[mi];
              if (!m) return;
              var imgs = (Array.isArray(m.images) ? m.images : []).filter(isSafeFrontUrl).slice(0, 9);
              var lbItems = imgs.map(function (u) {
                return { src: u, orig: extractOrigUrl(u), alt: (m.mood ? m.mood + ' · ' : '') + (m.date || '') };
              });
              openLightbox(lbItems, pi);
            });
          });
          feed.querySelectorAll('.moment-photo-img').forEach(function (im) {
            if (im.complete && im.naturalWidth > 0) return;
            im.classList.add('img-fade');
            var done = function () { im.classList.add('is-loaded'); recalcMetrics(); };
            im.addEventListener('load', done, { once: true });
            im.addEventListener('error', done, { once: true });
          });

          if (moreWrap) {
            if (filtered.length > limit) {
              moreWrap.innerHTML = '<button type="button" class="moments-more-btn">展开更多碎碎念（还有 ' + (filtered.length - limit) + ' 条）</button>';
              moreWrap.querySelector('button').addEventListener('click', function () {
                limit += 15;
                renderFeed();
              });
            } else {
              moreWrap.innerHTML = '';
            }
          }
          recalcMetrics();
        }

        renderBar();
        renderFeed();
      })
      .catch(function () {
        feed.innerHTML = '<div class="empty-state">碎碎念加载失败，请稍后刷新重试～</div>';
      });
  }

  function hydratePage(animate) {
    if (animate) animateStageCards();
    enhanceImages();
    enhanceVideos();
    enhanceCodeBlocks();
    initArticleExtras();
    initArticleStats();
    initArchiveYears();
    initComments();
    initGallery();
    initAbout();
    initMoments();
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
    if (/\.(xml|json|ico|png|jpg|jpeg|webp|gif|svg|css|js|pdf|zip|mp4|webm|mov|ogg|mp3|m4a|flac|wav)$/i.test(url.pathname)) return false;
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

  // Mobile instant prefetch on touchstart (~100ms head-start before tap release!)
  document.addEventListener('touchstart', function (e) {
    if (!e.target || !e.target.closest) return;
    var a = e.target.closest('a');
    if (!a) {
      var card = e.target.closest('.post-card');
      if (card) a = card.querySelector('.post-card-title a');
    }
    if (!isInternalPageLink(a)) return;
    var u = new URL(a.href, window.location.origin);
    if (u.pathname === window.location.pathname && u.search === window.location.search) return;
    fetchHtml(u.href).catch(function () {});
  }, { passive: true, capture: true });

  function saveCurrentScroll(updateHistory) {
    var y = Math.max(0, Math.round(window.scrollY || root.scrollTop || 0));
    scrollMemo.set(currentUrlKey, y);
    while (scrollMemo.size > 60) {
      scrollMemo.delete(scrollMemo.keys().next().value);
    }
    if (updateHistory) {
      try {
        history.replaceState({ url: window.location.href, scrollY: y }, '', window.location.href);
      } catch (_) {}
    }
  }

  function smoothNavigate(urlObj, push, restoreY) {
    closeLightbox();
    closeTocSheet();
    closeCmdSearch();
    document.querySelectorAll('video').forEach(function (v) { try { v.pause(); } catch (_) {} });
    if (!stage || isNavigating) {
      window.location.href = urlObj.href;
      return;
    }
    if (urlObj.pathname === window.location.pathname && urlObj.search === window.location.search) {
      if (typeof restoreY === 'number') {
        window.scrollTo(0, restoreY);
      } else if (urlObj.hash) {
        var anchor = document.querySelector(urlObj.hash);
        if (anchor) anchor.scrollIntoView({ behavior: reducedMotion ? 'auto' : 'smooth' });
      } else {
        window.scrollTo({ top: 0, behavior: reducedMotion ? 'auto' : 'smooth' });
      }
      return;
    }

    saveCurrentScroll(!!push);
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
        if (push) history.pushState({ url: urlObj.href, scrollY: 0 }, '', urlObj.href);
        currentUrlKey = urlObj.pathname + urlObj.search;

        if (typeof restoreY === 'number' && restoreY > 0) {
          window.scrollTo(0, restoreY);
        } else if (urlObj.hash) {
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
        if (typeof restoreY === 'number' && restoreY > 0) {
          requestAnimationFrame(function () {
            window.scrollTo(0, restoreY);
            paintScroll();
          });
        }
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

  window.addEventListener('popstate', function (e) {
    var dest = new URL(window.location.href);
    var destKey = dest.pathname + dest.search;
    var savedY = (e.state && typeof e.state.scrollY === 'number')
      ? e.state.scrollY
      : (scrollMemo.has(destKey) ? scrollMemo.get(destKey) : 0);
    smoothNavigate(dest, false, savedY);
  });

  document.addEventListener('keydown', function (e) {
    if ((e.ctrlKey || e.metaKey) && (e.key === 'k' || e.key === 'K')) {
      e.preventDefault();
      if (cmdEl && cmdEl.classList.contains('is-open')) closeCmdSearch();
      else openCmdSearch();
      return;
    }
    if (cmdEl && cmdEl.classList.contains('is-open')) {
      if (e.key === 'Escape') { e.preventDefault(); closeCmdSearch(); }
      else if (e.key === 'ArrowDown' && cmdHits.length) {
        e.preventDefault();
        cmdActiveIdx = (cmdActiveIdx + 1) % cmdHits.length;
        updateCmdActive();
      } else if (e.key === 'ArrowUp' && cmdHits.length) {
        e.preventDefault();
        cmdActiveIdx = (cmdActiveIdx - 1 + cmdHits.length) % cmdHits.length;
        updateCmdActive();
      } else if (e.key === 'Enter' && cmdHits.length) {
        e.preventDefault();
        jumpCmdIndex(cmdActiveIdx);
      }
      return;
    }
    if (tocSheetEl && tocSheetEl.classList.contains('is-open')) {
      if (e.key === 'Escape') { e.preventDefault(); closeTocSheet(); }
      return;
    }
    if (lb.el && lb.el.classList.contains('is-open')) {
      if (e.key === 'Escape') { e.preventDefault(); closeLightbox(); }
      else if (e.key === 'ArrowLeft') { e.preventDefault(); stepLightbox(-1); }
      else if (e.key === 'ArrowRight') { e.preventDefault(); stepLightbox(1); }
      else if (e.key === '+' || e.key === '=') { e.preventDefault(); zoomLightboxAt(lb.scale * 1.25, window.innerWidth / 2, window.innerHeight / 2, true); }
      else if (e.key === '-') { e.preventDefault(); zoomLightboxAt(lb.scale * 0.8, window.innerWidth / 2, window.innerHeight / 2, true); }
      else if (e.key === '0') { e.preventDefault(); setLightboxZoom(false); }
      return;
    }
    var tag = document.activeElement ? document.activeElement.tagName : '';
    if (e.key === '/' && tag !== 'INPUT' && tag !== 'TEXTAREA' && !(document.activeElement && document.activeElement.isContentEditable)) {
      var inp = document.getElementById('search-input');
      if (inp) {
        e.preventDefault();
        inp.focus();
      } else {
        e.preventDefault();
        openCmdSearch();
      }
    }
  });

  try {
    history.replaceState({ url: window.location.href, scrollY: window.scrollY || 0 }, '', window.location.href);
  } catch (_) {}
  hydratePage(false);
  initBgmPlayer();
  if (document.fonts && document.fonts.ready) {
    document.fonts.ready.then(function () { updateNavState(); });
  }
})();
