// trend kit: the page shell. Writes the record name and tab strip into
// the <header> just before this script, from the site's config
// (site.js, window.TREND_SITE), so every page of a site shares one tab
// list and every site shares one header. Load synchronously right after
// the header element: no layout shift, no flash of an empty header.
//
//   <header class="trend"></header><script src="kit/shell.js"></script>
//
// A Quarto page (trend.ice) has no .viz-root wrapper; the shell then
// puts the class on <body> so the kit's tokens and type apply there.
(function () {
  const S = window.TREND_SITE;
  const here = document.currentScript;
  const hdr = here && here.previousElementSibling;
  if (!S || !hdr || hdr.tagName !== "HEADER") return;
  const HUB = "https://australianantarcticdivision.github.io/trend/";
  const page = location.pathname.split("/").pop() || "index.html";
  const esc = s => String(s).replace(/[&<>"]/g, c =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
  const on = href => (href === page ||
    (S.alias && S.alias[page] === href)) ? ' class="on"' : "";
  const tabs = (S.tabs || []).map(([href, label]) =>
    `<a href="${href}"${on(href)}>${esc(label)}</a>`).join("");
  const ext = [{ href: HUB, label: "trend family",
                 title: "all the trend.* records: sea surface temperature, sea level, chlorophyll, sea ice" },
               ...(S.links || [])].map(l =>
    `<a class="ext" href="${l.href}" title="${esc(l.title || "")}">${esc(l.label)}</a>`).join("");
  const gh = S.repo ? `<a class="gh" href="${S.repo}" title="source repository" aria-label="GitHub repository"><svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path fill="currentColor" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8z"/></svg></a>` : "";
  hdr.classList.add("trend");
  hdr.innerHTML = `<h1><a href="index.html">${esc(S.title)}</a></h1>` +
    `<nav class="tabs">${tabs}${ext}${gh}</nav>`;
  // a Quarto page (kit/quarto.css) has no .viz-root wrapper of its own
  if (!hdr.closest(".viz-root")) document.body.classList.add("viz-root", "prose", "quarto");
})();
