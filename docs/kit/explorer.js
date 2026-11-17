// trend kit: the S2 cell explorer, every site's landing page.
//
// Reads the site's config (site.js: window.TREND_SITE.explorer) and the
// family registry (records.js). The page provides #app and #tip; this
// module builds everything inside #app. Data contract (per source id,
// written by the record's exporter):
//   data/cells-<id>.json   { months, regions, cells: [{ id, ring, mean,
//                            trend, anom, w, lon, lat, sring? }] }
//   data/monthly-<id>.bin  Float32 cells x months, cell-major
//   data/<weights>         optional, named by the cells JSON "weights":
//                          Float32 cells x months of cell weights, used in
//                          place of the static w where coverage varies
//   data/coast-110m.json   coastline mesh (self-hosted, see updateCoast)
//
// explorer config:
//   sources  ids of this record's sources and combos, first loaded first
//   family   "record:source" keys loaded from another record's site
//   view     default view: world | tmerc | ortho | longlat | spilhaus | faces
//   rotate   initial [lambda, phi]: the globe centres on (-lambda, -phi),
//            the flat views and tmerc use -lambda as central meridian
//   tmerc    { frame, radius, lon0 }: the tmerc view's frame, "south" |
//            "north" | "both" polar caps of that radius; lon0 pins its
//            central meridian (else it shares the others', -rotate[0])
(function () {
const SITE = window.TREND_SITE, RECS = window.TREND_RECORDS;
const HOME = SITE.record, XC = SITE.explorer || {};
const $ = s => document.querySelector(s);
const css = v => getComputedStyle($(".viz-root")).getPropertyValue(v).trim();
const tip = $("#tip");
const showTip = (h, x, y) => { tip.innerHTML = h; tip.style.display = "block";
  tip.style.left = (x + 14) + "px"; tip.style.top = (y + 14) + "px"; };
const hideTip = () => tip.style.display = "none";

const BLUE = ["#cde2fb","#9ec5f4","#6da7ec","#3987e5","#256abf","#184f95","#0d366b"];
const VIEWS = [["world", "World"], ["tmerc", "Transverse Mercator"],
               ["ortho", "Globe"], ["longlat", "Longlat"],
               ["spilhaus", "Spilhaus"], ["faces", "Cube net"]];
const withFmt = M => Object.fromEntries(Object.entries(M).map(([k, m]) =>
  [k, { ...m, fmt: v => v.toFixed(m.digits) }]));

// a source key is "id" (this record) or "record:id" (a family member's,
// read from its own site); combos are pairs within one record
function srcDef(key) {
  const [r, id] = key.includes(":") ? key.split(":") : [HOME, key];
  const rec = RECS[r];
  if (!rec) throw new Error("unknown record " + r);
  const base = r === HOME ? "data/" : rec.site + "data/";
  const pre = r === HOME ? "" : rec.label + ": ";
  const c = rec.combos && rec.combos[id];
  if (c) return { key, r, rec, id, base, combo: c, label: pre + c.label,
    a: r === HOME ? c.a : r + ":" + c.a, b: r === HOME ? c.b : r + ":" + c.b,
    metrics: withFmt(c.metrics) };
  const s = rec.sources[id];
  if (!s) throw new Error(`unknown source ${id} in ${r}`);
  return { key, r, rec, id, base, label: pre + (s.long || s.label),
           metrics: withFmt(rec.metrics) };
}
const HINT = {
  ortho: "Drag to rotate, wheel to zoom.",
  world: "Drag to spin the central meridian, wheel to zoom.",
  longlat: "Drag to spin the central meridian, wheel to zoom.",
  tmerc: "Drag to pan, shift-drag to turn the central meridian, wheel to zoom.",
  spilhaus: "Drag to pan, wheel to zoom.",
  faces: "Drag to pan, wheel to zoom."
};

const DATA = {};
// UI state survives source switches: selection travels by cell ID
const UI = { metric: "trend", view: XC.view || "world", panelView: "time",
             total: false,
             selIds: [], selLabel: null, regionKey: "",
             rotate: (XC.rotate || [155, 10]).slice(), scale: null,
             pan: { x: 0, y: 0, k: 1 },
             llk: 1, llty: 0, eek: 1, eety: 0, tmk: 1, tmo: null,
             coast: !!XC.coast, codeLang: "r" };
function fetchSource(d) {
  if (DATA[d.key]) return Promise.resolve(DATA[d.key]);
  const f = `${d.base}cells-${d.id}.json`, b = `${d.base}monthly-${d.id}.bin`;
  const bin = u => fetch(u).then(r => r.ok ? r.arrayBuffer() : Promise.reject(u));
  const meta = fetch(f).then(r => r.ok ? r.json() : Promise.reject(f));
  // monthly weights, when the export names a file (a bare name beside
  // the cells JSON); its fetch starts as soon as the JSON is in, and
  // without it the series falls back to the static w
  const wts = meta.then(m => /^[\w.-]+\.bin$/.test(m.weights || "")
    ? bin(d.base + m.weights).catch(() => (console.warn(`${m.weights} unavailable: using w`), null))
    : null);
  return Promise.all([meta, bin(b), wts]).then(([meta, buf, wbuf]) => {
    const monthly = new Float32Array(buf);
    let wm = wbuf ? new Float32Array(wbuf) : null;
    if (wm && wm.length !== monthly.length) {
      console.warn(`${meta.weights}: ${wm.length} values for ${monthly.length}; using w`);
      wm = null;
    }
    return (DATA[d.key] = { meta, monthly, wm });
  });
}
const fail = e => $("#app").innerHTML =
  `<div class="err">Could not load ${e}. ${SITE.dataHint ||
    "Run data-raw/export_site.R and commit docs/data/."}</div>`;
function loadSource(key) {
  let d;
  try { d = srcDef(key); } catch (e) { fail(e.message); return; }
  if (d.combo) {
    const da = srcDef(d.a), db = srcDef(d.b);
    Promise.all([fetchSource(da), fetchSource(db)])
      .then(([a, b]) => build(d, diffMeta(a.meta, b.meta), null, { a, b, da, db }))
      .catch(fail);
  } else {
    fetchSource(d).then(x => build(d, x.meta, x.monthly, null, x.wm)).catch(fail);
  }
}
// shared cells only; every metric becomes a - b
function diffMeta(ma, mb) {
  const ib = new Map(mb.cells.map((c, i) => [c.id, i]));
  const cells = [];
  ma.cells.forEach((c, ia) => {
    const i = ib.get(c.id);
    if (i == null) return;
    const cb = mb.cells[i];
    const d = { id: c.id, ring: c.ring, lon: c.lon, lat: c.lat,
      ia, ib: i, wa: c.w, wb: cb.w,
      mean: +(c.mean - cb.mean).toFixed(2),
      trend: c.trend != null && cb.trend != null
        ? +(c.trend - cb.trend).toFixed(3) : null,
      anom: c.anom != null && cb.anom != null
        ? +(c.anom - cb.anom).toFixed(2) : null };
    if (c.sring) d.sring = c.sring;
    cells.push(d);
  });
  const dix = new Map(cells.map((c, i) => [c.id, i]));
  const regions = {};
  for (const [k, r] of Object.entries(ma.regions || {})) {
    regions[k] = { label: r.label,
      cells: r.cells.map(i => dix.get(ma.cells[i].id)).filter(i => i != null) };
  }
  return { source: "diff", months: ma.months, regions, cells };
}
loadSource((XC.sources || [])[0] || Object.keys(RECS[HOME].sources)[0]);

function build(D, meta, monthly, aux, wm) {
  const MET = D.metrics, REC = D.rec, isCombo = !!D.combo;
  if (!(UI.metric in MET)) UI.metric = Object.keys(MET)[0];
  const cells = meta.cells, nm = meta.months.length;
  // rings arrive slerp-densified (28 pts) but the renderer keeps only
  // the 4 corners: S2 edges are great circles, exactly the curve d3's
  // adaptive resampler interpolates, so each view densifies each edge
  // only as far as it actually curves there -- adaptive densification
  // in the browser. Measured: halves render time, ~7x less path data
  // than projecting the baked points every frame; pixel-diff vs dense
  // rings is antialiasing jitter only.
  const corners = r => r.length === 28 ? r.filter((q, j) => j % 7 === 0) : r;
  const feats = cells.map((c, i) => {
    const f = { type: "Feature", idx: i,
      geometry: { type: "Polygon",
        coordinates: [[...corners(c.ring), c.ring[0]]] } };
    // d3-geo polygons are spherical: a ring wound the wrong way is the
    // sphere-complement (everything except the cell). Self-correct by
    // area: a level-5 cell is tiny, so > hemisphere means rewind.
    if (d3.geoArea(f) > Math.PI) f.geometry.coordinates[0].reverse();
    return f;
  });

  const opt = k => { const d = srcDef(k); return `<option value="${k}">${d.label}</option>`; };
  const own = (XC.sources || []).map(opt).join("");
  const fam = (XC.family || []).filter(k => RECS[k.split(":")[0]]).map(opt).join("");
  const unitOf = R => R.unit ? " " + R.unit : "";
  const total = REC.total && !isCombo ? REC.total : null;
  $("#app").innerHTML = `
    <div class="controls">
      <label>Source <select id="cellsrc">
        ${fam ? `<optgroup label="${RECS[HOME].title}">${own}</optgroup>` +
                `<optgroup label="trend family">${fam}</optgroup>` : own}
      </select></label>
      <label>View <select id="view">
        ${VIEWS.map(([k, l]) => `<option value="${k}">${l}</option>`).join("")}
      </select></label>
      <label><input type="checkbox" id="coast"> Coastline</label>
      <label>Color by <select id="metric">
        ${Object.entries(MET).map(([k, m]) =>
          `<option value="${k}">${m.label}</option>`).join("")}
      </select></label>
      <label id="regwrap">Region <select id="regionsel">
        <option value="">Preset...</option>
      </select></label>
      <button class="btn" id="clear">Clear selection</button>
      <span id="selinfo"></span>
    </div>
    <div class="cols">
      <div><svg id="globe"></svg><div class="legend">
        <canvas id="ramp" width="180" height="10"></canvas><span id="ramplab"></span>
        <span id="vhint" class="muted"></span>
      </div></div>
      <div class="panel">
        <h2 id="ptitle">Region series</h2>
        <div id="pviewwrap" class="controls" style="margin:4px 0 6px">
          <span class="seg" id="pseg">
            <button data-v="time" class="on">Time</button>
            <button data-v="doy">Seasonal</button></span>
          ${total ? `<span class="seg" id="tseg">
            <button data-t="0">Mean</button>
            <button data-t="1">${total.label}</button></span>` : ""}
        </div>
        <p class="note" id="pnote">Click cells on the map; the monthly series
        of the union is an area-weighted combination of cell sums.</p>
        <svg id="pchart"></svg>
        <div id="codewrap" style="display:none; margin-top:10px">
          <div class="controls" style="margin:0 0 6px">
            <span class="seg" id="cseg">
              <button data-l="r">R</button>
              <button data-l="sql">SQL</button>
              <button data-l="py">Python</button></span>
            <button class="btn" id="copycode">Copy</button>
            <span id="codemeta" style="font-size:12px"></span>
          </div>
          <pre id="codebox"></pre>
        </div>
      </div>
    </div>`;

  const wrapW = Math.min(1760, document.querySelector(".wrap").clientWidth);
  const size = Math.max(420, Math.min(innerHeight - 230, wrapW - 470, 1200));
  const svg = d3.select("#globe").attr("width", size).attr("height", size);
  const proj = d3.geoOrthographic()
    .translate([size / 2, size / 2]).scale(UI.scale || size / 2 - 8)
    .rotate(UI.rotate).clipAngle(90).precision(.7);
  // precision(.7): adaptive resampling ON, fed corner-only rings (see
  // corners() above) -- the resampler is the densifier now, emitting
  // vertices only where the current view bends an edge beyond ~a pixel
  const path = d3.geoPath(proj);
  // longlat: longitude/latitude used directly as plot coordinates --
  // NOT eqc/plate carree, nothing is scaled to metres, the angles never
  // leave angular space before becoming pixels. d3 cuts rings at the
  // antimeridian; drag spins the central meridian (shared with the
  // globe) and, when zoomed, slides north-south.
  const llProj = d3.geoEquirectangular()
    .fitExtent([[8, 8], [size - 8, size - 8]], { type: "Sphere" });
  const llBase = llProj.scale();
  const llLim = () => Math.max(0, (Math.PI * llProj.scale() - size) / 2);
  llProj.scale(llBase * (UI.llk || 1)).rotate([UI.rotate[0], 0])
    .translate([size / 2, size / 2 +
      Math.max(-llLim(), Math.min(llLim(), UI.llty || 0))])
    .precision(.7)
    // planar viewport cull: longlat lacks the globe's free
    // back-hemisphere clip, and zoomed-in it would otherwise project
    // and paint the whole world offscreen every frame
    .clipExtent([[0, 0], [size, size]]);
  const llPath = d3.geoPath(llProj);
  // world: Equal Earth (Savric, Patterson & Jenny 2018). Equal-area, so a
  // patch's screen area is in proportion to its ocean area (Robinson
  // inflates the high latitudes, the Southern Ocean most). The svg takes
  // the map's own ~2:1 aspect instead of the square; drag spins the
  // central meridian (shared with the globe), zoomed-in it also slides.
  const eeProj = d3.geoEqualEarth().fitWidth(size - 16, { type: "Sphere" });
  const eeB = d3.geoPath(eeProj).bounds({ type: "Sphere" });
  const eeH = Math.ceil(eeB[1][1] - eeB[0][1]) + 16;
  eeProj.fitExtent([[8, 8], [size - 8, eeH - 8]], { type: "Sphere" });
  // projected sphere [height, width] per unit scale (unclipped copies)
  const sphereHW = mk => {
    const b = d3.geoPath(mk().scale(1).translate([0, 0])).bounds({ type: "Sphere" });
    return [b[1][1] - b[0][1], b[1][0] - b[0][0]];
  };
  const FLAT = {
    longlat: { p: llProj, path: llPath, base: llBase, H: size, k: "llk", ty: "llty",
               hw: sphereHW(d3.geoEquirectangular) },
    world: { p: eeProj, path: d3.geoPath(eeProj), base: eeProj.scale(), H: eeH,
             k: "eek", ty: "eety", hw: sphereHW(d3.geoEqualEarth) }
  };
  const fLim = F => Math.max(0, (F.hw[0] * F.p.scale() - F.H) / 2);
  eeProj.scale(FLAT.world.base * (UI.eek || 1)).rotate([UI.rotate[0], 0])
    .translate([size / 2, eeH / 2 +
      Math.max(-fLim(FLAT.world), Math.min(fLim(FLAT.world), UI.eety || 0))])
    .precision(.7).clipExtent([[0, 0], [size, eeH]]);
  // tmerc: transverse Mercator, central meridian -rotate[0] (shared with
  // the globe and the flat views), as +proj=tmerc +lon_0=<that>. The
  // central meridian runs through both poles, so a polar cap sits near
  // the line of true scale and the projection is conformal: the
  // Southern Ocean view of seaice.map, with the pole near the middle.
  // Framed (explorer.tmerc.frame) on a spherical cap round one pole,
  // "south" (the default) or "north", or on both: the two poles lie on
  // the central meridian, so ONE transverse Mercator holds both caps,
  // joined along lon_0 and its antimeridian. Panned freely; the
  // offset is kept in projection units (tmo), so zoom about the centre
  // leaves it unchanged and a resize keeps the view. d3 clips the
  // transverse aspect's two singular points (the equator 90 degrees
  // either side of the central meridian) itself.
  const TM = XC.tmerc || {};
  const tmFrame = TM.frame || ((TM.lat ?? -90) > 0 ? "north" : "south");
  const tmPole = lat => d3.geoCircle().center([0, lat]).radius(TM.radius ?? 50)().coordinates;
  const tmCap = tmFrame === "both"
    ? { type: "MultiPolygon", coordinates: [tmPole(-90), tmPole(90)] }
    : { type: "Polygon", coordinates: tmPole(tmFrame === "north" ? 90 : -90) };
  // tmerc.lon0 pins this view's central meridian (its own, turned by
  // shift-drag), so e.g. a Pacific-centred world view can sit beside a
  // transverse Mercator on 115E; unset, it shares the other views'
  const tmOwn = TM.lon0 != null;
  if (tmOwn && UI.tmRot == null) UI.tmRot = -TM.lon0;
  const tmRot = () => tmOwn ? UI.tmRot : UI.rotate[0];
  const tmProj = d3.geoTransverseMercator().rotate([tmRot(), 0])
    .fitExtent([[8, 8], [size - 8, size - 8]], tmCap)
    .precision(.7).clipExtent([[0, 0], [size, size]]);
  const tmBase = tmProj.scale();
  if (!UI.tmo) UI.tmo = [(tmProj.translate()[0] - size / 2) / tmBase,
                         (tmProj.translate()[1] - size / 2) / tmBase];
  const tmSet = () => tmProj.translate([size / 2 + UI.tmo[0] * tmProj.scale(),
                                        size / 2 + UI.tmo[1] * tmProj.scale()]);
  const tmClamp = () => {
    UI.tmo[0] = Math.max(-1.6, Math.min(1.6, UI.tmo[0]));
    UI.tmo[1] = Math.max(-2.2, Math.min(2.2, UI.tmo[1]));
  };
  tmProj.scale(tmBase * (UI.tmk || 1)); tmSet();
  const tmPath = d3.geoPath(tmProj);
  const pathOf = v => v === "tmerc" ? tmPath : FLAT[v] ? FLAT[v].path : path;
  const viewH = () => view === "world" ? eeH : size;
  const byId = new Map(cells.map((c, i) => [c.id, i]));
  const sel = new Set(UI.selIds.map(id => byId.get(id)).filter(i => i != null));
  let selLabel = UI.selLabel;
  let metric = UI.metric;
  let view = UI.view;
  const saveSel = () => { UI.selIds = [...sel].map(i => cells[i].id);
                          UI.selLabel = selLabel; };

  // preset regions = the same named cell sets the series page uses;
  // a preset replaces the selection, then clicks edit it cell by cell
  const regionsel = $("#regionsel");
  if (meta.regions && Object.keys(meta.regions).length) {
    for (const [k, r] of Object.entries(meta.regions)) {
      const o = document.createElement("option");
      o.value = k; o.textContent = r.label; regionsel.appendChild(o);
    }
    regionsel.addEventListener("change", e => {
      const k = e.target.value;
      if (!k) return;
      sel.clear();
      for (const i of meta.regions[k].cells) sel.add(i);
      selLabel = meta.regions[k].label;
      UI.regionKey = k; saveSel();
      restyle(); drawSeries();
    });
    regionsel.value = UI.regionKey in meta.regions ? UI.regionKey : "";
  } else $("#regwrap").style.display = "none";

  $("#cellsrc").value = D.key;
  $("#cellsrc").addEventListener("change", e => loadSource(e.target.value));

  // "Get the data": runnable code for the current selection against the
  // public bucket -- the explorer doubles as a query builder
  const EP = "projects.pawsey.org.au", BK = REC.bucket;
  function idLines(ids, q, ind) {
    const o = [];
    for (let i = 0; i < ids.length; i += 8)
      o.push(ind + ids.slice(i, i + 8).map(t => q + t + q).join(", "));
    return o.join(",\n");
  }
  function genCode(lang, ids, srcs, label) {
    const VAL = REC.value, CODE = REC.code;
    const hdr = `${ids.length} cell${ids.length > 1 ? "s" : ""}` +
      (label ? ` (${label})` : "") + ` selected in the ${REC.title} explorer;` +
      " " + CODE.hdr;
    const cc = lang === "r" ? "## " : lang === "sql" ? "-- " : "# ";
    // rclone parses ':' in an on-the-fly remote, so the endpoint URL is
    // quoted inside the (shell-quoted) remote string
    const note = [
      "This reads the AUTHORITATIVE store: daily sufficient statistics",
      "(n, sumw, sumwx, sumwx2) per S2 cell, one parquet per date on",
      ...CODE.store,
      "an unfiltered read takes minutes; the date filter below keeps",
      "the default quick. (The website itself reads small baked",
      "monthly JSON derived from these sums -- downstream, hence fast.)",
      "For intensive work, bulk-sync the sums first and query locally:",
      `  rclone copy ":s3,provider=Ceph,endpoint='https://${EP}':${BK}/sums/" sums/`,
      ...CODE.source
    ].map(l => cc + l).join("\n");
    const [va, vb] = (D.combo && D.combo.vars) || ["a", "b"];
    // srcs: per source, the stores (sums/<store>/) it reads; more than
    // one when a source spans stores (one per hemisphere), unioned
    const multi = srcs.some(x => x.length > 1);
    const rq = x => x.length > 1 ? `c(${x.map(y => `"${y}"`).join(", ")})` : `"${x[0]}"`;
    const pq = x => x.length > 1 ? `[${x.map(y => `"${y}"`).join(", ")}]` : `"${x[0]}"`;
    const sqlFrom = x => x.length > 1
      ? `[${x.map(y => `'s3://${BK}/sums/${y}/*.parquet'`).join(", ")}]`
      : `'s3://${BK}/sums/${x[0]}/*.parquet'`;
    const since = new Date(Date.now() - 3 * 31557600000)
      .toISOString().slice(0, 10);
    if (lang === "r") {
      let s = `## ${hdr}\n${note}\nlibrary(arrow)\nlibrary(dplyr)\n` +
        `ts <- s3_bucket("${BK}",\n` +
        `  endpoint_override = "https://${EP}",\n` +
        `  region = "", anonymous = TRUE)\n` +
        `cells <- c(\n${idLines(ids, '"', "  ")})\n` +
        `## widen or remove for the full record (slower, see note above)\n` +
        `since <- as.Date("${since}")\n\n` +
        `read_region <- function(src) {\n` +
        (multi
          ? `  ## one dataset per store (sums/<store>/), unioned: their cells are disjoint\n` +
            `  ds <- lapply(src, function(s) open_dataset(ts$path(paste0("sums/", s))))\n` +
            `  (if (length(ds) == 1) ds[[1]] else open_dataset(ds)) |>\n`
          : `  open_dataset(ts$path(paste0("sums/", src))) |>\n`) +
        `    filter(cell %in% cells, date >= since) |>\n` +
        `    group_by(date) |>\n` +
        `    summarise(n = sum(n), sumw = sum(sumw),\n` +
        `              sumwx = sum(sumwx), sumwx2 = sum(sumwx2)) |>\n` +
        `    collect() |> arrange(date) |>\n` +
        `    mutate(mean = sumwx / sumw,\n` +
        `           var = pmax(0, sumwx2 / sumw - mean^2))\n}\n`;
      s += srcs.length === 2
        ? `${va} <- read_region(${rq(srcs[0])})\n${vb} <- read_region(${rq(srcs[1])})\n` +
          `d <- inner_join(${va}[c("date", "mean")], ${vb}[c("date", "mean")],\n` +
          `                by = "date", suffix = c("_${va}", "_${vb}")) |>\n` +
          `  mutate(diff = mean_${va} - mean_${vb})\n`
        : `d <- read_region(${rq(srcs[0])})\n`;
      s += `\n## Seasonal slices are FILE-LIST pruning here: the layout\n` +
        `## partitions by date in the filename, so e.g. every December\n` +
        `## across the whole record reads no off-month bytes at all:\n` +
        `# dec <- grep("-12-", ts$ls("sums/${srcs[0][0]}"), value = TRUE)\n` +
        `# d12 <- open_dataset(dec, filesystem = ts) |>\n` +
        `#   filter(cell %in% cells) |> group_by(date) |>\n` +
        `#   summarise(sumw = sum(sumw), sumwx = sum(sumwx)) |>\n` +
        `#   collect() |> mutate(mean = sumwx / sumw)\n`;
      return s;
    }
    if (lang === "sql") {
      return `-- ${hdr}\n${note}\n-- duckdb\nINSTALL httpfs; LOAD httpfs;\n` +
        `SET s3_endpoint='${EP}';\n` +
        `SET s3_url_style='path'; SET s3_region='';\n\n` +
        `SELECT date, SUM(sumwx) / SUM(sumw) AS ${VAL}\n` +
        `FROM read_parquet(${sqlFrom(srcs[0])})\n` +
        `WHERE date >= DATE '${since}'  -- remove for the full record\n` +
        `  AND cell IN (\n${idLines(ids, "'", "  ")})\n` +
        `GROUP BY date ORDER BY date;\n` +
        (srcs.length === 2
          ? `-- repeat with sums/${srcs[1].join(" + sums/")} and join on date for the difference\n`
          : "") +
        `\n-- seasonal slice: the date is the FILENAME, so a glob prunes\n` +
        `-- files before any bytes are read (every December, all years):\n` +
        `--   FROM read_parquet('s3://${BK}/sums/${srcs[0][0]}/????-12-*.parquet')\n`;
    }
    const q3 = '"' + '"' + '"';
    return `# ${hdr}\n${note}\nimport duckdb\n\ncells = [\n${idLines(ids, '"', "    ")}]\n` +
      `con = duckdb.connect()\n` +
      `con.sql("INSTALL httpfs; LOAD httpfs")\n` +
      `con.sql("SET s3_endpoint='${EP}'; SET s3_url_style='path'; SET s3_region=''")\n\n` +
      `def read_region(src):\n` +
      `    ids = ", ".join("'" + c + "'" for c in cells)\n` +
      (multi
        ? `    # one glob per store (sums/<store>/), read as one table\n` +
          `    paths = ", ".join(f"'s3://${BK}/sums/{s}/*.parquet'" for s in src)\n`
        : "") +
      `    return con.sql(f${q3}\n` +
      `        SELECT date, SUM(sumwx) / SUM(sumw) AS ${VAL}\n` +
      (multi
        ? `        FROM read_parquet([{paths}])\n`
        : `        FROM read_parquet('s3://${BK}/sums/{src}/*.parquet')\n`) +
      `        WHERE date >= DATE '${since}'  -- remove for the full record\n` +
      `          AND cell IN ({ids}) GROUP BY date ORDER BY date${q3}).df()\n\n` +
      (srcs.length === 2
        ? `${va} = read_region(${pq(srcs[0])})\n${vb} = read_region(${pq(srcs[1])})\n` +
          `d = ${va}.merge(${vb}, on="date", suffixes=("_${va}", "_${vb}"))\n` +
          `d["diff"] = d.${VAL}_${va} - d.${VAL}_${vb}\n`
        : `d = read_region(${pq(srcs[0])})\n`) +
      `\n# seasonal slice: the date is the FILENAME, so a glob prunes files\n` +
      `# before any bytes are read (every December, all years):\n` +
      `#   read_parquet('s3://${BK}/sums/${srcs[0][0]}/????-12-*.parquet')\n`;
  }
  function renderCode() {
    const wrap = $("#codewrap");
    if (!sel.size) { wrap.style.display = "none"; return; }
    wrap.style.display = "";
    for (const x of $("#cseg").children)
      x.classList.toggle("on", x.dataset.l === UI.codeLang);
    const ids = [...sel].map(i => cells[i].id).sort();
    // a source may span stores by hemisphere (records.js sources[k].stores,
    // store -> "s" | "n"): the code reads only those holding the selection
    const hemis = new Set([...sel].map(i => cells[i].lat < 0 ? "s" : "n"));
    const storesOf = k => {
      const st = REC.sources[k]?.stores;
      if (!st) return [k];
      const x = Object.keys(st).filter(y => hemis.has(st[y]));
      return x.length ? x : Object.keys(st);
    };
    const srcs = (isCombo ? [D.combo.a, D.combo.b] : [D.id]).map(storesOf);
    $("#codebox").textContent = genCode(UI.codeLang, ids, srcs, selLabel);
    $("#codemeta").textContent = "";
  }
  $("#cseg").addEventListener("click", e => {
    const b = e.target.closest("button"); if (!b) return;
    UI.codeLang = b.dataset.l; renderCode();
  });
  $("#copycode").addEventListener("click", () => {
    navigator.clipboard.writeText($("#codebox").textContent).then(
      () => { $("#codemeta").textContent = "copied"; },
      () => { $("#codemeta").textContent = "select + copy manually"; });
  });

  let panelView = UI.panelView;
  for (const x of $("#pseg").children)
    x.classList.toggle("on", x.dataset.v === panelView);
  if (isCombo) $("#pviewwrap").style.display = "none";
  $("#pseg").addEventListener("click", e => {
    const b = e.target.closest("button"); if (!b) return;
    panelView = UI.panelView = b.dataset.v;
    for (const x of $("#pseg").children) x.classList.toggle("on", x === b);
    drawSeries();
  });
  // a record with a total (sea ice area) can show the union's sum
  // instead of its mean; cells' w is then their mean daily ocean area
  const useTotal = () => !!(total && UI.total);
  if (total) {
    for (const x of $("#tseg").children)
      x.classList.toggle("on", (x.dataset.t === "1") === UI.total);
    $("#tseg").addEventListener("click", e => {
      const b = e.target.closest("button"); if (!b) return;
      UI.total = b.dataset.t === "1";
      for (const x of $("#tseg").children) x.classList.toggle("on", x === b);
      drawSeries();
    });
  }
  const valFmt = v => useTotal()
    ? v.toFixed(total.digits) + " " + total.unit
    : v.toFixed(REC.digits) + unitOf(REC);

  // Spilhaus: planar paths from PROJ-projected rings baked by the
  // exporter (sring, km). Absent sring (older data, seam cells) = hidden.
  const hasSpil = cells.some(c => c.sring);
  if (!hasSpil) {
    $("#view").querySelector('option[value="spilhaus"]').remove();
    if (view === "spilhaus") view = UI.view = "ortho";
  }
  let spd = null, nseam = 0;
  if (hasSpil) {
    let xmin = 1/0, xmax = -1/0, ymin = 1/0, ymax = -1/0;
    for (const c of cells) if (c.sring)
      for (const [x, y] of c.sring) {
        if (x < xmin) xmin = x; if (x > xmax) xmax = x;
        if (y < ymin) ymin = y; if (y > ymax) ymax = y;
      }
    const k = (size - 20) / Math.max(xmax - xmin, ymax - ymin);
    const ox = (size - k * (xmax - xmin)) / 2, oy = (size - k * (ymax - ymin)) / 2;
    const px = x => ox + (x - xmin) * k, py = y => oy + (ymax - y) * k;
    spd = cells.map(c => c.sring
      ? "M" + c.sring.map(p => px(p[0]).toFixed(1) + "," + py(p[1]).toFixed(1)).join("L") + "Z"
      : null);
    nseam = cells.filter(c => !c.sring).length;
  }

  // S2 cube net: each cell in its face's uv square via the gnomonic
  // face projection (S2's own geometry); 2x3 layout, seams explicit
  const faceOf = id => Math.floor(parseInt(id[0], 16) / 2);
  const uvOf = (f, x, y, z) => {
    switch (f) {
      case 0: return [y / x, z / x];
      case 1: return [-x / y, z / y];
      case 2: return [-x / z, -y / z];
      case 3: return [z / x, y / x];
      case 4: return [z / y, -x / y];
      default: return [-y / z, -x / z];
    }
  };
  // S2 staircase net: 0,1 bottom-left rising to 4,5 top-right; with
  // each face in native uv orientation every staircase seam is
  // edge-continuous (no rotations) -- the coastline proves it
  const FS = (size - 32) / 4, FM = 16;
  const FPOS = [[0, 2], [1, 2], [1, 1], [2, 1], [2, 0], [3, 0]];
  const faceXY = f => [FM + FPOS[f][0] * FS, FM + FPOS[f][1] * FS];
  const fcPaths = cells.map(c => {
    const f = faceOf(c.id), o = faceXY(f);
    // corners are EXACT here: cell edges are lines of constant u or v,
    // straight in the face's native uv by construction
    const pts = corners(c.ring).map(([lon, lat]) => {
      const cl = Math.cos(lat * Math.PI / 180);
      const uv = uvOf(f, cl * Math.cos(lon * Math.PI / 180),
                         cl * Math.sin(lon * Math.PI / 180),
                         Math.sin(lat * Math.PI / 180));
      const u = Math.max(-1, Math.min(1, uv[0]));
      const v = Math.max(-1, Math.min(1, uv[1]));
      return (o[0] + (u + 1) / 2 * FS).toFixed(1) + "," +
             (o[1] + (1 - v) / 2 * FS).toFixed(1);
    });
    return "M" + pts.join("L") + "Z";
  });

  const root = svg.append("g");
  const ffg = root.append("g").style("display", "none");
  for (let f = 0; f < 6; f++) {
    const o = faceXY(f);
    ffg.append("rect").attr("x", o[0]).attr("y", o[1])
      .attr("width", FS).attr("height", FS)
      .attr("fill", "none").attr("stroke", css("--border"));
    ffg.append("text").attr("x", o[0] + 4).attr("y", o[1] + 12)
      .attr("font-size", 10).attr("fill", css("--text-muted"))
      .text("face " + f);
  }

  // coastline overlay (context only, never interactive); drawn by d3 on
  // the globe, by per-face gnomonic projection on the net (polylines
  // split at face changes); not available in Spilhaus (rings are baked
  // server-side and no browser spilhaus projection exists here)
  const coastP = root.append("path").attr("fill", "none")
    .attr("stroke-width", 1.2).attr("vector-effect", "non-scaling-stroke")
    .style("pointer-events", "none")
    .style("display", "none");
  let landMesh = null, coastNetD = null;
  function facesCoast(mesh) {
    const out = [];
    for (const line of mesh.coordinates) {
      let cur = -1, pts = [];
      for (const [lon, lat] of line) {
        const cl = Math.cos(lat * Math.PI / 180);
        const x = cl * Math.cos(lon * Math.PI / 180),
              y = cl * Math.sin(lon * Math.PI / 180),
              z = Math.sin(lat * Math.PI / 180);
        const ax = Math.abs(x), ay = Math.abs(y), az = Math.abs(z);
        const fc = ax >= ay && ax >= az ? (x > 0 ? 0 : 3)
                 : ay >= az ? (y > 0 ? 1 : 4) : (z > 0 ? 2 : 5);
        if (fc !== cur) {
          if (pts.length > 1) out.push("M" + pts.join("L"));
          pts = []; cur = fc;
        }
        const uv = uvOf(fc, x, y, z), o = faceXY(fc);
        pts.push((o[0] + (uv[0] + 1) / 2 * FS).toFixed(1) + "," +
                 (o[1] + (1 - uv[1]) / 2 * FS).toFixed(1));
      }
      if (pts.length > 1) out.push("M" + pts.join("L"));
    }
    return out.join("");
  }
  function updateCoast() {
    if (!UI.coast || view === "spilhaus") {
      coastP.style("display", "none"); return;
    }
    if (!landMesh) {
      // self-hosted: this used to come from a second CDN (jsdelivr,
      // while the page scripts come from cdnjs) and failed silently on
      // networks that block one but not the other. Baked GeoJSON mesh
      // (Natural Earth 1:110m land via world-atlas, 2dp), 76 kB.
      d3.json("data/coast-110m.json")
        .then(m => {
          landMesh = m;
          coastNetD = facesCoast(m);
          updateCoast();
        }).catch(() => {});
      return;
    }
    // raise above the cells: the coastline runs exactly where coastal
    // cells sit, so drawn below them it was almost entirely hidden
    coastP.raise().style("display", null)
      .attr("stroke", css("--text-primary")).attr("stroke-opacity", .9)
      .attr("d", view === "faces" ? coastNetD : pathOf(view)(landMesh));
  }
  const grat = root.append("path")
    .datum(d3.geoGraticule10())
    .attr("fill", "none").attr("stroke-width", .5);
  const sphere = root.append("path").datum({ type: "Sphere" })
    .attr("fill", "none").attr("stroke-width", 1);
  const gc = root.append("g");
  const cellP = gc.selectAll("path").data(feats).join("path")
    .attr("stroke-width", .5)
    .attr("vector-effect", "non-scaling-stroke")
    .on("mousemove", (ev, f) => {
      const c = cells[f.idx], m = MET[metric];
      const v = c[metric];
      showTip(`<b>${c.id}</b> (${c.lat}, ${c.lon})<br>` +
        `${m.label}: ${v == null ? "-" : m.fmt(v)}<br>` + REC.tip(c),
        ev.clientX, ev.clientY);
    })
    .on("mouseleave", hideTip)
    .on("click", (ev, f) => {
      if (moved) return;   // the end of a drag, not a click
      sel.has(f.idx) ? sel.delete(f.idx) : sel.add(f.idx);
      selLabel = null; regionsel.value = ""; UI.regionKey = "";
      saveSel();
      restyle(); drawSeries();
    });

  function ramps() {
    const mid = css("--div-mid");
    return {
      div: t => t < .5
        ? d3.interpolateRgbBasis([BLUE[6], BLUE[3], BLUE[0], mid])(t * 2)
        : d3.interpolateRgbBasis([mid, "#f3b0a9", "#e34948", "#8f1f1e"])((t - .5) * 2),
      seq: d3.interpolateRgbBasis(BLUE)
    };
  }

  function colorOf(c) {
    const m = MET[metric], v = c[metric], R = ramps();
    if (v == null || !isFinite(v)) return css("--surface-2");
    if (m.type === "div") {
      const t = Math.max(-1, Math.min(1, v / m.lim)) / 2 + .5;
      return R.div(t);
    }
    const [lo, hi] = d3.extent(cells, q => q.mean);
    return R.seq((v - lo) / (hi - lo));
  }

  function restyle() {
    grat.attr("stroke", css("--grid"));
    sphere.attr("stroke", css("--border"));
    cellP.attr("fill", f => colorOf(cells[f.idx]))
      .attr("stroke", f => sel.has(f.idx) ? css("--text-primary") : css("--surface-1"))
      .attr("stroke-width", f => sel.has(f.idx) ? 1.6 : .5);
    cellP.filter(f => sel.has(f.idx)).raise();
    drawRamp();
    $("#selinfo").textContent = sel.size ? `${sel.size} cell${sel.size > 1 ? "s" : ""} selected` : "";
  }

  const pan = UI.pan;
  // pointer events outrun display frames (120-250/s on some devices,
  // each previously triggering a full reprojection of every cell);
  // coalesce to at most one render per animation frame
  let raf = 0;
  const requestRender = () => {
    if (!raf) raf = requestAnimationFrame(() => { raf = 0; render(); });
  };
  function render() {
    const planar = view === "spilhaus" ? spd
                 : view === "faces" ? fcPaths : null;
    ffg.style("display", view === "faces" ? null : "none");
    svg.attr("height", viewH());
    $("#vhint").textContent = HINT[view] || "";
    if (!planar) {
      root.attr("transform", null);
      const P = pathOf(view);
      grat.style("display", null).attr("d", P);
      // the transverse Mercator has no finite outline
      sphere.style("display", view === "tmerc" ? "none" : null).attr("d", P);
      cellP.style("display", null).attr("d", P);
    } else {
      root.attr("transform",
        `translate(${pan.x},${pan.y}) scale(${pan.k})`);
      grat.style("display", "none");
      sphere.style("display", "none");
      cellP.style("display", f => planar[f.idx] ? null : "none")
        .attr("d", f => planar[f.idx]);
    }
    updateCoast();
  }

  function drawRamp() {
    const cv = $("#ramp"), cx = cv.getContext("2d"), m = MET[metric], R = ramps();
    for (let i = 0; i < 180; i++) {
      cx.fillStyle = m.type === "div" ? R.div(i / 179)
        : R.seq(i / 179);
      cx.fillRect(i, 0, 1, 10);
    }
    const [lo, hi] = m.type === "div" ? [-m.lim, m.lim] : d3.extent(cells, q => q.mean);
    $("#ramplab").textContent = `${m.fmt(lo)} to ${m.fmt(hi)}` +
      (view === "spilhaus" && nseam
        ? ` (${nseam} seam cell${nseam > 1 ? "s" : ""} hidden)` : "");
  }

  // drag: rotate the globe, spin/slide the longlat rectangle, pan (or
  // shift: turn) the transverse Mercator, or pan the planar views; wheel
  // zooms all
  // moved: the pointer travelled > 4 px since pointerdown, so the click
  // the browser fires after pointerup ends a drag and selects nothing
  let drag = null, moved = false;
  svg.on("pointerdown", ev => {
       moved = false;
       drag = [ev.clientX, ev.clientY,
               view === "ortho" ? proj.rotate()
             : view === "tmerc" ? [tmProj.rotate()[0], UI.tmo[0], UI.tmo[1]]
             : FLAT[view] ? [FLAT[view].p.rotate()[0], FLAT[view].p.translate()[1]]
             : { ...pan }]; })
     .on("pointermove", ev => {
       if (!drag) return;
       if (!moved && Math.hypot(ev.clientX - drag[0], ev.clientY - drag[1]) > 4)
         moved = true;
       const dx = ev.clientX - drag[0], dy = ev.clientY - drag[1];
       if (view === "ortho") {
         const k = 90 / proj.scale();
         proj.rotate([drag[2][0] + dx * k,
                      Math.max(-90, Math.min(90, drag[2][1] - dy * k))]);
         UI.rotate = proj.rotate();
       } else if (view === "tmerc") {
         if (ev.shiftKey) {
           // turn: the central meridian; about the pole, ~180 degrees per view width
           tmProj.rotate([drag[2][0] + dx * 180 / size, 0]);
           if (tmOwn) UI.tmRot = tmProj.rotate()[0]; else UI.rotate[0] = tmProj.rotate()[0];
         } else {
           const s = tmProj.scale();
           UI.tmo = [drag[2][1] + dx / s, drag[2][2] + dy / s];
           tmClamp(); tmSet();
         }
       } else if (FLAT[view]) {
         // degrees of longitude per pixel along the equator
         const F = FLAT[view], p = F.p, k = 360 / (F.hw[1] * p.scale());
         p.rotate([drag[2][0] + dx * k, 0]);
         UI.rotate[0] = p.rotate()[0];
         const L = fLim(F), c = F.H / 2;
         const ty = Math.max(c - L, Math.min(c + L, drag[2][1] + dy));
         p.translate([size / 2, ty]);
         UI[F.ty] = ty - c;
       } else {
         pan.x = drag[2].x + dx;
         pan.y = drag[2].y + dy;
       }
       requestRender();
     })
     .on("pointerup pointerleave", () => drag = null)
     .on("wheel", ev => {
       ev.preventDefault();
       const f = ev.deltaY < 0 ? 1.12 : 0.9;
       if (view === "ortho") {
         proj.scale(Math.max(size / 4, Math.min(size * 2, proj.scale() * f)));
         UI.scale = proj.scale();
       } else if (view === "tmerc") {
         tmProj.scale(Math.max(tmBase / 2, Math.min(tmBase * 12, tmProj.scale() * f)));
         UI.tmk = tmProj.scale() / tmBase; tmSet();
       } else if (FLAT[view]) {
         const F = FLAT[view], p = F.p;
         p.scale(Math.max(F.base, Math.min(F.base * 10, p.scale() * f)));
         UI[F.k] = p.scale() / F.base;
         const L = fLim(F), c = F.H / 2;
         const ty = Math.max(c - L, Math.min(c + L, p.translate()[1]));
         p.translate([size / 2, ty]);
         UI[F.ty] = ty - c;
       } else {
         const k2 = Math.max(.5, Math.min(8, pan.k * f)), r = k2 / pan.k;
         pan.x = size / 2 + (pan.x - size / 2) * r;
         pan.y = size / 2 + (pan.y - size / 2) * r;
         pan.k = k2;
       }
       requestRender();
     });

  $("#view").value = view;
  $("#metric").value = metric;
  $("#coast").checked = UI.coast;
  $("#coast").addEventListener("change", e => {
    UI.coast = e.target.checked; updateCoast();
  });
  $("#view").addEventListener("change", e => {
    view = UI.view = e.target.value;
    pan.x = 0; pan.y = 0; pan.k = 1;
    // every view shares the central meridian: the view follows you
    // (tmerc unless its own is pinned, tmerc.lon0)
    proj.rotate(UI.rotate);
    llProj.rotate([UI.rotate[0], 0]);
    eeProj.rotate([UI.rotate[0], 0]);
    tmProj.rotate([tmRot(), 0]);
    render(); drawRamp();
  });
  $("#metric").addEventListener("change", e => {
    metric = UI.metric = e.target.value; restyle();
  });
  $("#clear").addEventListener("click", () => {
    sel.clear(); selLabel = null; regionsel.value = ""; UI.regionKey = "";
    saveSel();
    restyle(); drawSeries();
  });
  window._mapRedraw = () => { restyle(); drawSeries(); };
  window._mapRebuild = () => build(D, meta, monthly, aux, wm);
  if (!window._mapMM) {
    window._mapMM = true;
    matchMedia("(prefers-color-scheme: dark)").addEventListener("change",
      () => window._mapRedraw());
    let rt = null;
    addEventListener("resize", () => {
      clearTimeout(rt);
      rt = setTimeout(() => window._mapRebuild(), 250);
    });
  }

  // region series from cell sums: one line per source (a combo overlays
  // both), area-weighted combination computed client-side
  function drawSeries() {
    const svg2 = d3.select("#pchart"); svg2.selectAll("*").remove();
    const w = Math.min(720, $(".panel").clientWidth), h = 320;
    svg2.attr("width", w).attr("height", h);
    if (!sel.size) { $("#ptitle").textContent = "Region series";
      renderCode(); return; }
    $("#ptitle").textContent = `Region series (${selLabel ? selLabel + ", " : ""}` +
      `${sel.size} cell${sel.size > 1 ? "s" : ""})`;
    renderCode();
    const idx = [...sel];
    const tot = useTotal();
    const mkpts = (mn, months, getV, getW) => {
      const pts = [];
      for (let m = 0; m < mn; m++) {
        let sw = 0, swx = 0;
        for (const i of idx) {
          const v = getV(i, m);
          if (isFinite(v)) { const wi = getW(i, m); sw += wi; swx += wi * v; }
        }
        if (sw > 0) pts.push({ d: new Date(months[m] + "-15"),
                               v: tot ? swx * total.scale : swx / sw });
      }
      return pts;
    };
    let series;
    if (isCombo) {
      const A = aux.a, B = aux.b, nA = A.meta.months.length, nB = B.meta.months.length;
      const sa = REC.sources[D.combo.a], sb = REC.sources[D.combo.b];
      series = [
        { label: sa.label, col: css(sa.col || "--series-2"),
          pts: mkpts(nA, A.meta.months,
                     (i, m) => A.monthly[cells[i].ia * nA + m],
                     A.wm ? (i, m) => A.wm[cells[i].ia * nA + m] : i => cells[i].wa) },
        { label: sb.label, col: css(sb.col || "--series-1"),
          pts: mkpts(nB, B.meta.months,
                     (i, m) => B.monthly[cells[i].ib * nB + m],
                     B.wm ? (i, m) => B.wm[cells[i].ib * nB + m] : i => cells[i].wb) }];
    } else {
      series = [{ label: null, col: css("--series-1"),
        pts: mkpts(nm, meta.months, (i, m) => monthly[i * nm + m],
                   wm ? (i, m) => wm[i * nm + m] : i => cells[i].w) }];
    }
    series = series.filter(s => s.pts.length);
    if (!series.length) return;
    if (panelView === "doy" && !isCombo) {
      drawSeasonal(svg2, w, h, series[0]); return;
    }
    const all = series.flatMap(s => s.pts);
    const M = { t: 12, r: 52, b: 26, l: 42 };
    const x = d3.scaleTime().domain(d3.extent(all, p => p.d)).range([M.l, w - M.r]);
    const y = d3.scaleLinear().domain(d3.extent(all, p => p.v)).nice()
      .range([h - M.b, M.t]);
    const ax = g => { g.selectAll("path,line").attr("stroke", css("--grid"));
      g.selectAll("text").attr("fill", css("--text-secondary")).attr("font-size", 11); };
    svg2.append("g").attr("transform", `translate(0,${h - M.b})`)
      .call(d3.axisBottom(x).ticks(6).tickSizeOuter(0)).call(ax);
    svg2.append("g").attr("transform", `translate(${M.l},0)`)
      .call(d3.axisLeft(y).ticks(5).tickSize(-(w - M.l - M.r)).tickSizeOuter(0))
      .call(ax).call(g => g.selectAll(".tick line").attr("opacity", .5));
    const line = d3.line().x(p => x(p.d)).y(p => y(p.v));
    for (const s of series) {
      svg2.append("path").attr("d", line(s.pts)).attr("fill", "none")
        .attr("stroke", s.col).attr("stroke-width", 1.8);
      if (s.label) {
        const lp = s.pts[s.pts.length - 1];
        svg2.append("text").attr("x", x(lp.d) + 4).attr("y", y(lp.v))
          .attr("dominant-baseline", "middle").attr("font-size", 11)
          .attr("font-weight", 600).attr("fill", s.col).text(s.label);
      }
    }
    const hair = svg2.append("line").attr("y1", M.t).attr("y2", h - M.b)
      .attr("stroke", css("--text-muted")).attr("stroke-dasharray", "3 3")
      .style("display", "none");
    svg2.append("rect").attr("x", M.l).attr("y", M.t)
      .attr("width", w - M.l - M.r).attr("height", h - M.t - M.b)
      .attr("fill", "transparent")
      .on("mousemove", ev => {
        const d0 = x.invert(d3.pointer(ev)[0]);
        hair.attr("x1", x(d0)).attr("x2", x(d0)).style("display", null);
        const rows = series.map(s => {
          const p = s.pts[d3.bisector(q => q.d).center(s.pts, d0)];
          return `${s.label ? s.label + " " : ""}${p ? valFmt(p.v) : "-"}`;
        }).join("<br>");
        showTip(`<b>${d3.timeFormat("%Y-%m")(d0)}</b><br>${rows}`,
                ev.clientX, ev.clientY);
      })
      .on("mouseleave", () => { hair.style("display", "none"); hideTip(); });
  }

  // seasonal spaghetti (monthly resolution): every year gray, the
  // current year emphasized -- the ClimateReanalyzer-style sanity view
  // for ANY cell selection; the daily version for named regions is the
  // status page's day-of-year view
  function drawSeasonal(svg2, w, h, s) {
    const pts = s.pts.map(p => ({ y: p.d.getFullYear(),
                                  m: p.d.getMonth() + 1, v: p.v }));
    const byYear = d3.group(pts, p => p.y);
    const yrs = [...byYear.keys()].sort(d3.ascending);
    const cur = yrs[yrs.length - 1];
    const M = { t: 12, r: 46, b: 26, l: 42 };
    const x = d3.scaleLinear().domain([1, 12]).range([M.l, w - M.r]);
    const y = d3.scaleLinear().domain(d3.extent(pts, p => p.v)).nice()
      .range([h - M.b, M.t]);
    const ax = g => { g.selectAll("path,line").attr("stroke", css("--grid"));
      g.selectAll("text").attr("fill", css("--text-secondary")).attr("font-size", 11); };
    svg2.append("g").attr("transform", `translate(0,${h - M.b})`)
      .call(d3.axisBottom(x).ticks(12)
        .tickFormat(m => "JFMAMJJASOND"[m - 1]).tickSizeOuter(0)).call(ax);
    svg2.append("g").attr("transform", `translate(${M.l},0)`)
      .call(d3.axisLeft(y).ticks(5).tickSize(-(w - M.l - M.r)).tickSizeOuter(0))
      .call(ax).call(g => g.selectAll(".tick line").attr("opacity", .5));
    const line = d3.line().x(p => x(p.m)).y(p => y(p.v));
    for (const yr of yrs) if (yr !== cur) {
      svg2.append("path").attr("d", line(byYear.get(yr))).attr("fill", "none")
        .attr("stroke", css("--text-muted")).attr("stroke-opacity", .35)
        .attr("stroke-width", 1).attr("class", "pghost").attr("data-year", yr);
    }
    const cp = byYear.get(cur);
    svg2.append("path").attr("d", line(cp)).attr("fill", "none")
      .attr("stroke", s.col).attr("stroke-width", 2.2);
    const lp = cp[cp.length - 1];
    svg2.append("text").attr("x", x(lp.m) + 5).attr("y", y(lp.v))
      .attr("dominant-baseline", "middle").attr("font-size", 11)
      .attr("font-weight", 650).attr("fill", s.col).text(cur);
    svg2.append("rect").attr("x", M.l).attr("y", M.t)
      .attr("width", w - M.l - M.r).attr("height", h - M.t - M.b)
      .attr("fill", "transparent")
      .on("mousemove", ev => {
        const [px, py] = d3.pointer(ev);
        const mo = Math.max(1, Math.min(12, Math.round(x.invert(px))));
        let best = null;
        for (const yr of yrs) {
          const p = byYear.get(yr).find(q => q.m === mo);
          if (p && (!best || Math.abs(y(p.v) - py) < Math.abs(y(best.p.v) - py)))
            best = { yr, p };
        }
        svg2.selectAll(".pghost").attr("stroke-opacity", .35)
          .attr("stroke", css("--text-muted")).attr("stroke-width", 1);
        if (best) {
          if (best.yr !== cur)
            svg2.selectAll(`.pghost[data-year="${best.yr}"]`)
              .attr("stroke", css("--text-secondary")).attr("stroke-opacity", .9)
              .attr("stroke-width", 1.6);
          showTip(`<b>${best.yr}</b> month ${best.p.m}<br>${valFmt(best.p.v)}`,
                  ev.clientX, ev.clientY);
        }
      })
      .on("mouseleave", () => {
        svg2.selectAll(".pghost").attr("stroke-opacity", .35)
          .attr("stroke-width", 1);
        hideTip();
      });
  }

  restyle(); render(); drawSeries();
}
})();
