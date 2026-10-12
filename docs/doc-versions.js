// Version menu for the DocC pages on GitHub Pages. scripts/build-docs-site.py adds this script
// to every generated page and writes doc-versions.json next to it:
//
//   [{ "title": "2.5.0", "path": "2.5", "latest": true }, ..., { "title": "main", "path": "main" }]
//
// Every version lives at /<base>/<path>/documentation/...; the latest release is also at
// /<base>/documentation/..., which is where the menu sends readers who pick it.
(() => {
  const base = new URL(".", document.currentScript.src).pathname; // "/swift-kurrentdb/"
  const itemClass = "doc-version-menu";

  const style = document.createElement("style");
  style.textContent = `
    .${itemClass} { display: flex; align-items: center; gap: 0.25em; }
    .${itemClass} select {
      font: inherit; color: inherit; background: transparent;
      border: none; padding: 0; cursor: pointer;
    }
    /* The select inherits DocC's text colour; the drop-down list keeps the system colours. */
    .${itemClass} option { color: CanvasText; background: Canvas; }
    .${itemClass} select:focus-visible { outline: 2px solid var(--color-focus-color, #0071e3); }
  `;
  document.head.append(style);

  const versionsRequest = fetch(`${base}doc-versions.json`).then((response) => response.json());

  // "/swift-kurrentdb/2.4/documentation/kurrentdb/streams" → { version: "2.4", page: "kurrentdb/streams" }
  function currentPage(versions) {
    const path = window.location.pathname.slice(base.length);
    const [first, ...rest] = path.split("/");
    const named = versions.find((version) => version.path === first);
    const pagePath = named ? rest.join("/") : path;
    return {
      version: named ?? versions.find((version) => version.latest) ?? versions[0],
      page: pagePath.replace(/^documentation\//, "").replace(/\/$/, ""),
    };
  }

  function prefix(version) {
    return version.latest ? base : `${base}${version.path}/`;
  }

  // Stay on the same page when the other version has it, otherwise open its overview.
  async function open(version, page) {
    const root = prefix(version);
    const exists = await fetch(`${root}data/documentation/${page}.json`, { method: "HEAD" })
      .then((response) => response.ok, () => false);
    window.location.href = `${root}documentation/${exists ? page : page.split("/")[0]}/`;
  }

  function install(versions) {
    const items = document.querySelector(".nav-menu-items");
    if (!items || items.querySelector(`.${itemClass}`)) return;

    const current = currentPage(versions);
    const item = document.createElement("li");
    item.className = `nav-menu-item ${itemClass}`;
    const label = document.createElement("label");
    label.textContent = "Version:";
    const select = document.createElement("select");
    select.setAttribute("aria-label", "Documentation version");
    for (const version of versions) {
      select.add(new Option(version.title, version.path, false, version === current.version));
    }
    label.htmlFor = select.id = "doc-version-select";
    select.addEventListener("change", () => {
      const { page } = currentPage(versions);
      open(versions.find((version) => version.path === select.value), page);
    });
    item.append(label, select);
    items.prepend(item);
  }

  versionsRequest.then((versions) => {
    install(versions);
    // DocC renders the navigation bar itself and redraws it when the page changes.
    new MutationObserver(() => install(versions)).observe(document.body, { childList: true, subtree: true });
  }, () => {});
})();
