// trend kit: the mechanics page, the pipeline ledger. What the bucket
// holds (manifest.json, written by the backfill host at push time,
// fetched live) against what the site was built from (data/status.json,
// baked at export time). The page provides #out and #bucketlink.
(function () {
const SITE = window.TREND_SITE, REC = window.TREND_RECORDS[SITE.record];
const ST = REC.status || {};
const $ = s => document.querySelector(s);
const BUCKET = "https://projects.pawsey.org.au/" + REC.bucket;
// the site's own data files: the sources it exports, never a family member's
const OWN = (SITE.explorer?.sources || Object.keys(REC.sources))
  .filter(k => !k.includes(":") && REC.sources[k]);
const SITE_FILES = ["status.json", "series.json",
  ...OWN.flatMap(id => [`cells-${id}.json`, `monthly-${id}.bin`]),
  ...(SITE.extraFiles || []), "coast-110m.json"];
const fmtB = b => b == null ? "-"
  : b > 1e9 ? (b / 1e9).toFixed(2) + " GB"
  : b > 1e6 ? (b / 1e6).toFixed(1) + " MB"
  : Math.round(b / 1e3) + " kB";
const dayDiff = (a, b) => Math.round((new Date(a) - new Date(b)) / 864e5);
const chip = (cls, label) =>
  `<span class="chip"><span class="dot" style="background:var(--status-${cls})"></span>${label}</span>`;

const bl = $("#bucketlink");
if (bl) { bl.href = BUCKET + "/manifest.json"; bl.textContent = REC.bucket; }

async function main() {
  const out = $("#out");
  const site = await fetch("data/status.json").then(r => r.ok ? r.json() : null)
    .catch(() => null);
  let bucket = null, bucketErr = null;
  try {
    const r = await fetch(BUCKET + "/manifest.json?t=" + Date.now());
    if (r.ok) bucket = await r.json();
    else bucketErr = `manifest.json returned HTTP ${r.status} - not yet ` +
      `published? The backfill job writes it after each push ` +
      `(data-raw/write_manifest.R).`;
  } catch (e) {
    bucketErr = `Could not fetch the bucket manifest from the browser - ` +
      `most likely CORS is not enabled on the bucket (the object may still ` +
      `exist: <a class="mono" href="${BUCKET}/manifest.json">open it ` +
      `directly</a>). Enabling GET CORS on aad-derived unlocks this page ` +
      `and the live-query tier.`;
  }
  if (!site) { out.innerHTML = `<div class="err">data/status.json missing -
    ${SITE.dataHint || "run data-raw/export_site.R."}</div>`; return; }

  const today = new Date();
  const srcs = [...new Set([...Object.keys(site.sources || {}),
                            ...Object.keys(bucket?.sums || {})])];
  let html = "";

  if (bucketErr) html += `<div class="err">${bucketErr}</div>`;
  if (bucket) html += `<p class="sec">Bucket manifest written
    <span class="mono">${bucket.generated}</span> on
    <span class="mono">${bucket.host || "?"}</span>
    (GDAL ${bucket.gdal || "?"}). Site data baked
    <span class="mono">${site.generated}</span>.</p>`;

  for (const nm of srcs) {
    const b = bucket?.sums?.[nm], s = site.sources?.[nm];
    html += `<h2>${nm}${s?.label ? ` <span class="sub">${s.label}</span>` : ""}</h2><table>
      <tr><th>stage</th><th>dates</th><th>first</th><th>last</th>
          <th>gaps</th><th>size</th><th>as of</th></tr>
      <tr><td>bucket sums</td>
          <td class="mono">${b ? b.n.toLocaleString() : "-"}</td>
          <td class="mono">${b?.first || "-"}</td>
          <td class="mono">${b?.last || "-"}</td>
          <td class="mono">${b ? b.gaps : "-"}</td>
          <td class="mono">${fmtB(b?.bytes)}</td>
          <td class="mono">${b?.newest_write || (bucket ? "absent" : "unreachable")}</td></tr>
      <tr><td>site summaries</td>
          <td class="mono">${s ? s.n.toLocaleString() : "-"}</td>
          <td class="mono">${s?.first || "-"}</td>
          <td class="mono">${s?.last || "-"}</td>
          <td class="mono">${s ? s.gaps.length : "-"}</td>
          <td class="mono muted">derived</td>
          <td class="mono">${site.generated}</td></tr>
    </table>`;
    // verdicts
    const v = [];
    if (b && s) {
      const dn = b.n - s.n, dd = dayDiff(b.last, s.last);
      v.push(dn === 0 && dd === 0
        ? chip("good", "site summaries match the bucket")
        : chip("warning", `site behind bucket: ${dn} date${dn === 1 ? "" : "s"}` +
            (dd ? ` (${dd} day${dd === 1 ? "" : "s"} of tail)` : "") +
            ` - re-run the site export and commit`));
    } else if (s && !b && bucket) {
      v.push(chip("serious", "in site data but missing from the bucket manifest"));
    } else if (!b) {
      v.push(chip("serious", "bucket state unknown"));
    }
    if (b) {
      const behind = dayDiff(today, b.last), [f1, f2] = ST.fresh || [3, 10];
      v.push(ST.fixed ? chip("good", `${ST.fixed} (last ${b.last})`)
        : behind <= f1 ? chip("good", `bucket fresh (${behind} d behind today)`)
        : behind <= f2 ? chip("warning", `bucket lagging (${behind} d behind today)`)
        : chip("critical", `bucket stale (${behind} d behind today)`));
    }
    html += `<p>${v.join(" &nbsp; ")}</p>`;
  }

  html += `<h2>site data files</h2>
    <table id="files"><tr><th>file</th><th>size</th><th>last modified</th></tr>
    ${SITE_FILES.map(f => `<tr data-f="${f}"><td class="mono">
      <a href="data/${f}">data/${f}</a></td>
      <td class="mono">...</td><td class="mono">...</td></tr>`).join("")}
    </table>`;
  out.innerHTML = html;

  for (const f of SITE_FILES) {
    fetch("data/" + f, { method: "HEAD" }).then(r => {
      const tds = document.querySelector(`tr[data-f="${f}"]`).children;
      tds[1].textContent = r.ok ? fmtB(+r.headers.get("content-length")) : "missing";
      tds[2].textContent = r.headers.get("last-modified") || "-";
    }).catch(() => {});
  }
}
main();
})();
