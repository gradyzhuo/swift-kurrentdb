// Language switch and release-notes picker for the landing page.
//
// Without JavaScript the page still works: the markup ships in English
// (`<html data-lang="en">`) and every release article is visible.
(function () {
  var root = document.documentElement;
  root.classList.add('js');

  // ---- Language ------------------------------------------------------------
  // Priority: ?lang=… in the URL, then the visitor's last choice, then English.
  // There is deliberately no browser-language detection: English is the default.
  var LANGS = { en: 'en', zh: 'zh-Hant' };
  var STORAGE_KEY = 'swift-kurrentdb.lang';

  function readStored() {
    try { return window.localStorage.getItem(STORAGE_KEY); } catch (e) { return null; }
  }
  function writeStored(key) {
    try { window.localStorage.setItem(STORAGE_KEY, key); } catch (e) { /* private mode etc. */ }
  }

  function applyLang(key) {
    if (!LANGS[key]) key = 'en';
    root.setAttribute('data-lang', key);
    root.setAttribute('lang', LANGS[key]);
    document.querySelectorAll('[data-lang-switch]').forEach(function (button) {
      button.setAttribute('aria-pressed', String(button.getAttribute('data-lang-switch') === key));
    });
    // <option> text can't be hidden with CSS, so swap it.
    document.querySelectorAll('option[data-en]').forEach(function (option) {
      option.textContent = option.getAttribute(key === 'zh' ? 'data-zh' : 'data-en');
    });
    return key;
  }

  var fromQuery = new URLSearchParams(window.location.search).get('lang');
  var initial = applyLang(fromQuery || readStored() || 'en');
  if (fromQuery) writeStored(initial);

  document.querySelectorAll('[data-lang-switch]').forEach(function (button) {
    button.addEventListener('click', function () {
      writeStored(applyLang(button.getAttribute('data-lang-switch')));
    });
  });

  // ---- Release notes picker ------------------------------------------------
  // Shows one release at a time. #v2.1 in the URL opens that release; choosing
  // another release updates the hash with replaceState so it can be shared.
  var select = document.getElementById('release-select');
  var releases = Array.prototype.slice.call(document.querySelectorAll('.release'));

  function currentHash() {
    return decodeURIComponent(window.location.hash.slice(1));
  }

  function findRelease(id) {
    for (var i = 0; i < releases.length; i++) {
      if (releases[i].id === id) return releases[i];
    }
    return null;
  }

  function show(target, updateHash) {
    releases.forEach(function (release) { release.hidden = release !== target; });
    select.value = target.id;
    if (updateHash) {
      var url = window.location.pathname + window.location.search + '#' + target.id;
      window.history.replaceState(null, '', url);
    }
  }

  if (select && releases.length > 0) {
    // The first article is the latest release.
    show(findRelease(currentHash()) || releases[0], false);

    select.addEventListener('change', function () {
      show(findRelease(select.value) || releases[0], true);
    });
    // Only release hashes switch the release. Other anchors (#install, #api …)
    // are table-of-contents jumps and must not reset the chosen release.
    window.addEventListener('hashchange', function () {
      var target = findRelease(currentHash());
      if (target) show(target, false);
    });
  }

  // ---- Table of contents: highlight the section in view ----------------------
  var tocLinks = Array.prototype.slice.call(document.querySelectorAll('.toc a[href^="#"]'));
  if (tocLinks.length === 0 || !('IntersectionObserver' in window)) return;

  var linkFor = {};
  var sections = [];
  tocLinks.forEach(function (link) {
    var section = document.getElementById(link.getAttribute('href').slice(1));
    if (section) {
      linkFor[section.id] = link;
      sections.push(section);
    }
  });

  var visible = {};
  function markCurrent() {
    // The topmost section that is currently in the reading band wins.
    var current = null;
    for (var i = 0; i < sections.length; i++) {
      if (visible[sections[i].id]) { current = sections[i].id; break; }
    }
    if (!current) return; // between sections: keep the last highlight
    tocLinks.forEach(function (link) { link.removeAttribute('aria-current'); });
    linkFor[current].setAttribute('aria-current', 'true');
  }

  // The reading band is the upper part of the viewport, just below the top bar.
  var observer = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) { visible[entry.target.id] = entry.isIntersecting; });
    markCurrent();
  }, { rootMargin: '-72px 0px -55% 0px' });
  sections.forEach(function (section) { observer.observe(section); });
})();
