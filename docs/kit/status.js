// trend kit: the status page (store state, coverage, sanity series).
// The page provides #content, #gen and #tip; prose (sub line, footer)
// stays in the page. Reads data/status.json and data/series.json; per
// record settings come from records.js (status: fresh thresholds or a
// fixed-release label, ghost source for the day-of-year backdrop,
// default region, series units).
(function () {
const SITE = window.TREND_SITE, REC = window.TREND_RECORDS[SITE.record];
const ST = REC.status || {};
const $ = s => document.querySelector(s);
const css = v => getComputedStyle($(".viz-root")).getPropertyValue(v).trim();
const tip = $("#tip");
const showTip = (html, x, y) => { tip.innerHTML = html; tip.style.display = "block";
  tip.style.left = (x + 14) + "px"; tip.style.top = (y + 14) + "px"; };
const hideTip = () => tip.style.display = "none";
const fmtD = d3.timeFormat("%Y-%m-%d");
const SRC = REC.sources;
const lab = nm => SRC[nm]?.label || nm;
const col = nm => SRC[nm]?.col || "--series-1";
// series values: the record's own unit unless the status series is a
// different quantity (sea ice: area, not mean concentration)
const UNIT = ST.unit ?? REC.unit, DIG = ST.digits ?? REC.digits;
const val = v => v.toFixed(DIG) + (UNIT ? " " + UNIT : "");

Promise.all([
  fetch("data/status.json").then(r => r.ok ? r.json() : Promise.reject("status.json")),
  fetch("data/series.json").then(r => r.ok ? r.json() : Promise.reject("series.json"))
]).then(([status, series]) => build(status, series))
  .catch(e => $("#content").innerHTML =
    `<div class="err">Could not load ${e}. ${SITE.dataHint ||
      "Run data-raw/export_site.R."}</div>`);

function build(status, series) {
  $("#gen").textContent = (status.generated || "").replace("T", " ");
  const names = Object.keys(status.sources);
  const today = new Date();
  const el = $("#content");
  el.innerHTML = "";

  // ---- tiles: stat per source + freshness status (icon + label, never color alone)
  const tiles = document.createElement("div"); tiles.className = "tiles";
  for (const nm of names) {
    const s = status.sources[nm];
    const behind = Math.round((today - new Date(s.last)) / 864e5);
    const [f1, f2] = ST.fresh || [3, 10];
    // a fixed release: age is a property of the release, not lag
    const st = ST.fixed ? ["--status-good", ST.fixed]
             : behind <= f1 ? ["--status-good", "Fresh"]
             : behind <= f2 ? ["--status-warning", "Lagging"]
             : ["--status-critical", "Stale"];
    const t = document.createElement("div"); t.className = "tile";
    t.innerHTML = `<div class="name">${lab(nm)}</div>
      <div class="big">${s.last}</div>
      <div class="meta">${s.n.toLocaleString()} dates from ${s.first}
        &middot; ${s.gaps.length} gap${s.gaps.length === 1 ? "" : "s"}
        &middot; ${ST.meta || `last ${s.provisional_days} d provisional`}</div>
      <div class="chip"><span class="dot" style="background:var(${st[0]})"></span>
        ${st[1]}${ST.fixed ? "" : ` &middot; ${behind} day${behind === 1 ? "" : "s"} behind today`}</div>`;
    tiles.appendChild(t);
  }
  el.appendChild(tiles);

  // ---- coverage strip
  const sec1 = document.createElement("section");
  sec1.innerHTML = `<h2>Coverage</h2>
    <p class="note">One row per source: held dates, gaps, and the provisional tail.</p>
    <canvas id="cov"></canvas>
    <div class="legend">
      <span><span class="sw" style="background:var(--series-1);opacity:.55"></span>held</span>
      <span><span class="sw" style="background:var(--status-warning)"></span>provisional</span>
      <span><span class="sw" style="background:var(--status-critical)"></span>gap</span>
    </div>`;
  el.appendChild(sec1);
  drawCoverage(status, names);

  // ---- series explorer
  const sec2 = document.createElement("section");
  sec2.innerHTML = `<h2>Series</h2>
    <p class="note">${ST.note || "Area-weighted mean straight from the sums."} Day-of-year
    view: all years in gray, the current year emphasized.</p>
    <div class="controls">
      <span class="seg" id="viewseg">
        <button data-v="time" class="on">Time</button>
        <button data-v="doy">Day of year</button></span>
      <label>Region <select id="regsel"></select></label>
      <label id="srcwrap" style="display:none">Source <select id="srcsel"></select></label>
    </div>
    <svg id="chart"></svg>
    <div class="legend" id="chartleg"></div>`;
  el.appendChild(sec2);

  const state = { view: "time", region: ST.region || "cr",
                  src: names.length > 1 ? "both" : names[0] };
  const srcsel = $("#srcsel");
  if (names.length > 1) {
    const o = document.createElement("option");
    o.value = "both"; o.textContent = "Both"; srcsel.appendChild(o);
  }
  for (const nm of names) {
    const o = document.createElement("option");
    o.value = nm; o.textContent = lab(nm); srcsel.appendChild(o);
  }
  srcsel.value = state.src;
  const REGIONS = series.regions || { cr: "60S-60N", global: "Global" };
  if (!(state.region in REGIONS)) state.region = Object.keys(REGIONS)[0];
  const regsel = $("#regsel");
  for (const [k, l] of Object.entries(REGIONS)) {
    const o = document.createElement("option");
    o.value = k; o.textContent = l; regsel.appendChild(o);
  }
  regsel.value = state.region;
  $("#viewseg").addEventListener("click", e => {
    const b = e.target.closest("button"); if (!b) return;
    state.view = b.dataset.v;
    for (const x of $("#viewseg").children) x.classList.toggle("on", x === b);
    $("#srcwrap").style.display = state.view === "doy" ? "" : "none";
    draw();
  });
  $("#regsel").addEventListener("change", e => { state.region = e.target.value; draw(); });
  srcsel.addEventListener("change", e => { state.src = e.target.value; draw(); });
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change",
    () => { drawCoverage(status, names); draw(); });
  addEventListener("resize", () => { drawCoverage(status, names); draw(); });

  function dims(svg, h) {
    const w = Math.min(1100, $(".wrap").clientWidth);
    svg.attr("width", w).attr("height", h);
    return { w, h, m: { t: 14, r: 56, b: 28, l: 44 } };
  }

  function draw() {
    const svg = d3.select("#chart"); svg.selectAll("*").remove();
    const { w, h, m } = dims(svg, 340);
    const leg = $("#chartleg"); leg.innerHTML = "";
    if (state.view === "time") drawTime(svg, w, h, m, leg);
    else drawDoy(svg, w, h, m, leg);
  }

  function axisify(g) {
    g.selectAll("path,line").attr("stroke", css("--grid"));
    g.selectAll("text").attr("fill", css("--text-secondary")).attr("font-size", 11);
  }

  function drawTime(svg, w, h, m, leg) {
    const packs = names.map(nm => {
      const s = series.sources[nm];
      return { nm, col: css(col(nm)),
               pts: s.dates.map((d, i) => ({ d: new Date(d), v: s[state.region][i] }))
                     .filter(p => p.v != null) };
    }).filter(p => p.pts.length);
    const x = d3.scaleTime()
      .domain(d3.extent(packs.flatMap(p => [p.pts[0].d, p.pts[p.pts.length - 1].d])))
      .range([m.l, w - m.r]);
    const y = d3.scaleLinear()
      .domain(d3.extent(packs.flatMap(p => p.pts.map(q => q.v)))).nice()
      .range([h - m.b, m.t]);
    svg.append("g").attr("transform", `translate(0,${h - m.b})`)
      .call(d3.axisBottom(x).ticks(8).tickSizeOuter(0)).call(axisify);
    svg.append("g").attr("transform", `translate(${m.l},0)`)
      .call(d3.axisLeft(y).ticks(6).tickSize(-(w - m.l - m.r)).tickSizeOuter(0))
      .call(axisify).call(g => g.selectAll(".tick line").attr("opacity", .5));
    const line = d3.line().x(p => x(p.d)).y(p => y(p.v));
    for (const p of packs) {
      svg.append("path").attr("d", line(p.pts)).attr("fill", "none")
        .attr("stroke", p.col).attr("stroke-width", 1.6);
      const last = p.pts[p.pts.length - 1];
      svg.append("text").attr("x", x(last.d) + 5).attr("y", y(last.v))
        .attr("dominant-baseline", "middle").attr("font-size", 12)
        .attr("font-weight", 600).attr("fill", css("--text-primary"))
        .text(lab(p.nm));
      leg.insertAdjacentHTML("beforeend",
        `<span><span class="sw" style="background:${p.col}"></span>${lab(p.nm)}</span>`);
    }
    const hair = svg.append("line").attr("y1", m.t).attr("y2", h - m.b)
      .attr("stroke", css("--text-muted")).attr("stroke-dasharray", "3 3")
      .style("display", "none");
    svg.append("rect").attr("x", m.l).attr("y", m.t)
      .attr("width", w - m.l - m.r).attr("height", h - m.t - m.b)
      .attr("fill", "transparent")
      .on("mousemove", ev => {
        const d0 = x.invert(d3.pointer(ev)[0]);
        hair.attr("x1", x(d0)).attr("x2", x(d0)).style("display", null);
        const rows = packs.map(p => {
          const i = d3.bisector(q => q.d).center(p.pts, d0);
          const q = p.pts[i];
          return `<span style="color:${p.col}">&#9632;</span> ${lab(p.nm)}
                  ${q ? val(q.v) : "-"}`;
        }).join("<br>");
        showTip(`<b>${fmtD(d0)}</b><br>${rows}`, ev.clientX, ev.clientY);
      })
      .on("mouseleave", () => { hair.style("display", "none"); hideTip(); });
  }

  function drawDoy(svg, w, h, m, leg) {
    // "Both": the longer record supplies the gray climatological
    // backdrop; the current year is drawn once per source in its color,
    // so the products are compared on the same day axis and context.
    const srcs = state.src === "both" ? names : [state.src];
    const ghostSrc = srcs.includes(ST.ghost) ? ST.ghost
      : srcs.reduce((a, b) => status.sources[b].first < status.sources[a].first ? b : a);
    const toDoy = nm => {
      const s = series.sources[nm];
      return d3.group(s.dates.map((d, i) => ({ d, v: s[state.region][i] }))
        .filter(p => p.v != null)
        .map(p => ({ y: +p.d.slice(0, 4),
                     doy: d3.timeDay.count(new Date(+p.d.slice(0, 4), 0, 1), new Date(p.d)) + 1,
                     v: p.v })), p => p.y);
    };
    const byYear = Object.fromEntries(srcs.map(nm => [nm, toDoy(nm)]));
    const ghosts = byYear[ghostSrc];
    const yrs = [...ghosts.keys()].sort(d3.ascending);
    const cur = d3.max(srcs.flatMap(nm => [...byYear[nm].keys()]));
    const allPts = srcs.flatMap(nm => [...byYear[nm].values()].flat());
    const x = d3.scaleLinear().domain([1, 366]).range([m.l, w - m.r]);
    const y = d3.scaleLinear()
      .domain(d3.extent(allPts, p => p.v)).nice()
      .range([h - m.b, m.t]);
    svg.append("g").attr("transform", `translate(0,${h - m.b})`)
      .call(d3.axisBottom(x).tickValues([1, 60, 121, 182, 244, 305])
        .tickFormat(v => ["Jan", "Mar", "May", "Jul", "Sep", "Nov"][[1, 60, 121, 182, 244, 305].indexOf(v)])
        .tickSizeOuter(0)).call(axisify);
    svg.append("g").attr("transform", `translate(${m.l},0)`)
      .call(d3.axisLeft(y).ticks(6).tickSize(-(w - m.l - m.r)).tickSizeOuter(0))
      .call(axisify).call(g => g.selectAll(".tick line").attr("opacity", .5));
    const line = d3.line().x(p => x(p.doy)).y(p => y(p.v));
    for (const yr of yrs) if (yr !== cur) {
      svg.append("path").attr("d", line(ghosts.get(yr))).attr("fill", "none")
        .attr("stroke", css("--text-muted")).attr("stroke-opacity", .35)
        .attr("stroke-width", 1).attr("data-year", yr).attr("class", "ghost");
    }
    leg.innerHTML = "";
    srcs.forEach((nm, j) => {
      const pts = byYear[nm].get(cur);
      if (!pts || !pts.length) return;
      const c = css(col(nm));
      svg.append("path").attr("d", line(pts)).attr("fill", "none")
        .attr("stroke", c).attr("stroke-width", 2.2);
      const lastP = pts[pts.length - 1];
      svg.append("text").attr("x", x(lastP.doy) + 6)
        .attr("y", y(lastP.v) + (srcs.length > 1 ? (j ? 12 : -6) : 0))
        .attr("dominant-baseline", "middle").attr("font-size", 12)
        .attr("font-weight", 650).attr("fill", c)
        .text(srcs.length > 1 ? `${cur} ${lab(nm)}` : cur);
      leg.insertAdjacentHTML("beforeend",
        `<span><span class="sw" style="background:${c}"></span>${cur} ${lab(nm)}</span>`);
    });
    leg.insertAdjacentHTML("beforeend",
      `<span><span class="sw" style="background:${css("--text-muted")};opacity:.5"></span>
      ${yrs[0]}-${cur - 1} (${lab(ghostSrc)})</span>`);
    svg.append("rect").attr("x", m.l).attr("y", m.t)
      .attr("width", w - m.l - m.r).attr("height", h - m.t - m.b)
      .attr("fill", "transparent")
      .on("mousemove", ev => {
        const [px, py] = d3.pointer(ev);
        const doy = Math.round(x.invert(px));
        const cands = [];
        for (const yr of yrs) if (yr !== cur)
          cands.push({ lbl: `${yr}`, ghost: yr, arr: ghosts.get(yr) });
        for (const nm of srcs) {
          const arr = byYear[nm].get(cur);
          if (arr) cands.push({ lbl: `${cur} ${lab(nm)}`, arr });
        }
        let best = null;
        for (const c of cands) {
          const i = d3.bisector(p => p.doy).center(c.arr, doy);
          const p = c.arr[i];
          if (p && (!best || Math.abs(y(p.v) - py) < Math.abs(y(best.p.v) - py)))
            best = { ...c, p };
        }
        svg.selectAll(".ghost").attr("stroke", css("--text-muted"))
          .attr("stroke-opacity", .35).attr("stroke-width", 1);
        if (best) {
          if (best.ghost)
            svg.selectAll(`.ghost[data-year="${best.ghost}"]`)
              .attr("stroke", css("--text-secondary")).attr("stroke-opacity", .9)
              .attr("stroke-width", 1.6);
          showTip(`<b>${best.lbl}</b> day ${best.p.doy}<br>${val(best.p.v)}`,
                  ev.clientX, ev.clientY);
        }
      })
      .on("mouseleave", () => {
        svg.selectAll(".ghost").attr("stroke-opacity", .35).attr("stroke-width", 1);
        hideTip();
      });
  }

  function drawCoverage(status, names) {
    const cv = $("#cov");
    const w = Math.min(1100, $(".wrap").clientWidth), rowH = 26, gap = 10;
    const h = names.length * (rowH + gap) + 22;
    const dpr = devicePixelRatio || 1;
    cv.width = w * dpr; cv.height = h * dpr;
    cv.style.width = w + "px"; cv.style.height = h + "px";
    const cx = cv.getContext("2d"); cx.scale(dpr, dpr);
    const l = 64, r = 8;
    const t0 = d3.min(names, nm => new Date(status.sources[nm].first));
    const t1 = new Date();
    const x = d3.scaleTime().domain([t0, t1]).range([l, w - r]);
    cx.clearRect(0, 0, w, h);
    names.forEach((nm, i) => {
      const s = status.sources[nm];
      const yy = i * (rowH + gap);
      cx.fillStyle = css("--text-secondary");
      cx.font = "12px system-ui"; cx.textBaseline = "middle";
      cx.fillText(lab(nm), 0, yy + rowH / 2);
      cx.globalAlpha = .55; cx.fillStyle = css(col(nm));
      cx.fillRect(x(new Date(s.first)), yy,
                  x(new Date(s.last)) - x(new Date(s.first)), rowH);
      cx.globalAlpha = 1;
      cx.fillStyle = css("--status-warning");
      const p0 = new Date(s.last); p0.setDate(p0.getDate() - s.provisional_days);
      cx.fillRect(x(p0), yy, x(new Date(s.last)) - x(p0), rowH);
      cx.fillStyle = css("--status-critical");
      for (const g of s.gaps)
        cx.fillRect(x(new Date(g)) - .75, yy, 1.5, rowH);
    });
    const years = d3.timeYear.range(d3.timeYear.ceil(t0), t1, 4);
    cx.fillStyle = css("--text-muted"); cx.font = "11px system-ui";
    cx.textBaseline = "top";
    for (const yr of years) cx.fillText(yr.getFullYear(), x(yr), h - 16);
    cv.onmousemove = ev => {
      const rect = cv.getBoundingClientRect();
      const mx = ev.clientX - rect.left, my = ev.clientY - rect.top;
      const row = Math.floor(my / (rowH + gap));
      if (row < 0 || row >= names.length || mx < l) { hideTip(); return; }
      const nm = names[row], s = status.sources[nm];
      const d = fmtD(x.invert(mx));
      const state = s.gaps.includes(d) ? "gap"
        : d > s.last ? "not yet"
        : d >= fmtD(new Date(new Date(s.last) - s.provisional_days * 864e5))
          ? "provisional" : "held";
      showTip(`<b>${lab(nm)}</b> ${d}<br>${state}`, ev.clientX, ev.clientY);
    };
    cv.onmouseleave = hideTip;
  }

  draw();
}
})();
