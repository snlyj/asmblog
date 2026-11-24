(function () {
  var root = document.documentElement;
  var btn = document.getElementById('theme-toggle');

  function setTheme(mode) {
    root.setAttribute('data-theme', mode);
    localStorage.setItem('asmblog-theme', mode);
    if (btn) btn.textContent = mode === 'dark' ? '☀' : '◐';
  }

  var cur = root.getAttribute('data-theme') || 'light';
  if (btn) {
    btn.textContent = cur === 'dark' ? '☀' : '◐';
    btn.addEventListener('click', function () {
      cur = cur === 'dark' ? 'light' : 'dark';
      setTheme(cur);
    });
  }

  // Keyboard shortcut: press '/' to focus search input or jump to /search/
  document.addEventListener('keydown', function (e) {
    if (e.key === '/' && document.activeElement.tagName !== 'INPUT' && document.activeElement.tagName !== 'TEXTAREA') {
      var inp = document.getElementById('search-input');
      if (inp) {
        e.preventDefault();
        inp.focus();
      } else {
        e.preventDefault();
        window.location.href = '/search/';
      }
    }
  });

  // Zero-backend static instant search powered by /search-index.json
  var searchInput = document.getElementById('search-input');
  var resultsBox = document.getElementById('search-results');
  if (searchInput && resultsBox) {
    var indexCache = null;

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
        return;
      }
      var needle = q.toLowerCase();
      var hits = list.filter(function (p) {
        return (
          (p.title || '').toLowerCase().indexOf(needle) !== -1 ||
          (p.summary || '').toLowerCase().indexOf(needle) !== -1 ||
          (p.tags || '').toLowerCase().indexOf(needle) !== -1
        );
      });
      if (!hits.length) {
        resultsBox.innerHTML = '<div class="empty-state">没有找到与「' + esc(q) + '」相关的文章。</div>';
        return;
      }
      resultsBox.innerHTML = hits
        .map(function (p) {
          var tagsHtml = (p.tags || '')
            .split(',')
            .map(function (t) { return t.trim(); })
            .filter(Boolean)
            .map(function (t) {
              return '<a class="tag-chip" href="/tag/' + encodeURIComponent(t) + '/">#' + esc(t) + '</a>';
            })
            .join('');
          return (
            '<article class="post-card">' +
            '<div class="post-meta"><time>' + esc(p.date) + '</time></div>' +
            '<h2 class="post-card-title"><a href="/post/' + esc(p.slug) + '/">' + esc(p.title) + '</a></h2>' +
            '<p class="post-summary">' + esc(p.summary) + '</p>' +
            '<div class="tag-row">' + tagsHtml + '</div>' +
            '</article>'
          );
        })
        .join('');
    }

    function runSearch(q) {
      if (indexCache) {
        renderHits(indexCache, q);
        return;
      }
      fetch('/search-index.json')
        .then(function (r) { return r.json(); })
        .then(function (data) {
          indexCache = Array.isArray(data) ? data : [];
          renderHits(indexCache, q);
        })
        .catch(function () {});
    }

    searchInput.addEventListener('input', function () {
      runSearch(searchInput.value.trim());
    });

    // Support direct static navigation like /search/?q=asm even on pure file hosting
    var params = new URLSearchParams(window.location.search);
    var initQ = (params.get('q') || '').trim();
    if (initQ && !searchInput.value) {
      searchInput.value = initQ;
      runSearch(initQ);
    }
  }
})();
