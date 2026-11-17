// trend kit: the modes page (EOFs of the monthly cell export, written
// by data-raw/eof.py as data/eof-<id>.json). The page carries the prose
// and a JSON config block <script type="application/json" id="cfg">
// { sources: [{ id, label }], mode1?, oni? }; this module draws the
// pattern map, the time series and the checks card.
(function () {
  const $ = (id) => document.getElementById(id);
  const css = (v) => getComputedStyle(document.querySelector('.viz-root')).getPropertyValue(v).trim();
  const CFG = JSON.parse(document.getElementById('cfg').textContent);
  let E, C, coast, sel = 0, src = CFG.sources[0].id;
  const LON0 = 20;                      // map centred on the Pacific (200E)
  const X = (lon) => ((lon - LON0) % 360 + 360) % 360;

  function hex(c) { c = c.replace('#', ''); return [0, 2, 4].map(i => parseInt(c.slice(i, i + 2), 16)); }
  function ramp(v) {                    // v in [-1, 1]
    const neg = hex(css('--series-1')), pos = hex(css('--accent-warm')), mid = hex(css('--surface-2'));
    const a = Math.min(1, Math.abs(v)), end = v < 0 ? neg : pos;
    const t = Math.pow(a, 0.8);
    return 'rgb(' + mid.map((m, i) => Math.round(m + (end[i] - m) * t)).join(',') + ')';
  }
  function fit(cv) {
    const r = cv.getBoundingClientRect(), d = window.devicePixelRatio || 1;
    cv.width = Math.round(r.width * d); cv.height = Math.round(r.height * d);
    const g = cv.getContext('2d'); g.setTransform(d, 0, 0, d, 0, 0); return [g, r.width, r.height];
  }
  function scaleOf(p) {
    const a = p.filter(v => v !== null).map(Math.abs).sort((x, y) => x - y);
    const q = a[Math.floor(a.length * 0.98)] || 1;
    const nice = [0.1, 0.2, 0.25, 0.5, 1, 2, 5, 10, 20, 25, 50, 100, 200];
    return nice.find(n => n >= q) || q;
  }

  function drawMap() {
    const [g, w, h] = fit($('map'));
    const sx = w / 360, sy = h / 180, px = (x) => x * sx, py = (lat) => (90 - lat) * sy;
    const pat = E.modes[sel].pattern, s = scaleOf(pat);
    g.clearRect(0, 0, w, h);
    C.cells.forEach((c, i) => {
      const v = pat[i];
      if (v === null || v === undefined) return;
      let xs = c.ring.map(p => X(p[0]));
      const x0 = xs[0];
      xs = xs.map(x => x - x0 > 180 ? x - 360 : (x0 - x > 180 ? x + 360 : x));
      g.fillStyle = ramp(v / s);
      for (const off of [0, -360, 360]) {
        const mn = Math.min(...xs) + off, mx = Math.max(...xs) + off;
        if (mx < 0 || mn > 360) continue;
        g.beginPath();
        c.ring.forEach((p, k) => { const xx = px(xs[k] + off), yy = py(p[1]); k ? g.lineTo(xx, yy) : g.moveTo(xx, yy); });
        g.closePath(); g.fill();
      }
    });
    if (coast) {
      g.strokeStyle = css('--text-secondary'); g.lineWidth = 0.7; g.globalAlpha = 0.8;
      for (const line of coast.coordinates) {
        g.beginPath(); let prev = null;
        for (const p of line) {
          const x = X(p[0]);
          if (prev === null || Math.abs(x - prev) > 180) g.moveTo(px(x), py(p[1])); else g.lineTo(px(x), py(p[1]));
          prev = x;
        }
        g.stroke();
      }
      g.globalAlpha = 1;
    }
    // Nino 3.4 box
    g.strokeStyle = css('--text-primary'); g.lineWidth = 1; g.setLineDash([3, 3]);
    g.strokeRect(px(X(-170)), py(5), px(50), py(-5) - py(5)); g.setLineDash([]);
    $('unit').textContent = E.unit + ' per standard deviation of the time series';
    $('lo').textContent = '-' + s; $('hi').textContent = '+' + s;
    const bg = $('bar').getContext('2d');
    for (let i = 0; i < 180; i++) { bg.fillStyle = ramp(i / 89.5 - 1); bg.fillRect(i, 0, 1, 10); }
  }

  let pcGeom = null;
  function drawPC() {
    const [g, w, h] = fit($('pc'));
    const pc = E.modes[sel].pc, n = pc.length;
    const L = 34, R = 8, T = 8, B = 22;
    const lim = Math.max(3, Math.ceil(Math.max(...pc.map(Math.abs))));
    const x = (i) => L + (w - L - R) * i / (n - 1), y = (v) => T + (h - T - B) * (lim - v) / (2 * lim);
    pcGeom = { x, n, L, R, w };
    g.clearRect(0, 0, w, h);
    g.font = '11px system-ui, sans-serif'; g.fillStyle = css('--text-muted'); g.strokeStyle = css('--grid'); g.lineWidth = 1;
    for (let v = -lim; v <= lim; v += lim > 4 ? 2 : 1) {
      g.beginPath(); g.moveTo(L, y(v)); g.lineTo(w - R, y(v)); g.stroke();
      g.textAlign = 'right'; g.fillText(v > 0 ? '+' + v : String(v), L - 6, y(v) + 4);
    }
    g.textAlign = 'center';
    E.months.forEach((m, i) => {
      if (m.endsWith('-01') && (+m.slice(0, 4)) % 5 === 0) {
        g.beginPath(); g.moveTo(x(i), T); g.lineTo(x(i), h - B); g.stroke();
        g.fillText(m.slice(0, 4), x(i), h - 6);
      }
    });
    g.strokeStyle = css('--text-secondary'); g.beginPath(); g.moveTo(L, y(0)); g.lineTo(w - R, y(0)); g.stroke();
    for (const [sgn, col] of [[1, css('--accent-warm')], [-1, css('--series-1')]]) {
      g.fillStyle = col; g.globalAlpha = 0.35; g.beginPath(); g.moveTo(x(0), y(0));
      pc.forEach((v, i) => g.lineTo(x(i), y(sgn * v > 0 ? v : 0))); g.lineTo(x(n - 1), y(0)); g.closePath(); g.fill();
    }
    g.globalAlpha = 1; g.strokeStyle = css('--text-primary'); g.lineWidth = 1.2; g.beginPath();
    pc.forEach((v, i) => i ? g.lineTo(x(i), y(v)) : g.moveTo(x(i), y(v))); g.stroke();
  }

  function draw() {
    const m = E.modes[sel];
    document.querySelectorAll('#modes button').forEach((b, i) => b.classList.toggle('on', i === sel));
    $('stat').textContent = 'Mode ' + m.mode + ': ' + (100 * m.variance).toFixed(1) +
      '% of variance; correlation with the Nino 3.4 box anomaly ' + m.r_nino34_box.toFixed(2) + '.';
    $('pctitle').textContent = 'Mode ' + m.mode + ' time series (standard units)';
    drawMap(); drawPC();
  }

  $('pc').addEventListener('mousemove', (ev) => {
    if (!pcGeom) return;
    const r = ev.target.getBoundingClientRect(), fx = (ev.clientX - r.left - pcGeom.L) / (pcGeom.w - pcGeom.L - pcGeom.R);
    const i = Math.max(0, Math.min(pcGeom.n - 1, Math.round(fx * (pcGeom.n - 1))));
    $('readout').textContent = E.months[i] + ': ' + E.modes[sel].pc[i].toFixed(2) + ' sd';
  });
  $('pc').addEventListener('mouseleave', () => { $('readout').innerHTML = '&nbsp;'; });

  function checks() {
    const m1 = E.modes[0], yrs = {};
    E.months.forEach((m, i) => { const y = m.slice(0, 4); (yrs[y] = yrs[y] || []).push(m1.pc[i]); });
    const peak = (a, b) => { let best = null; E.months.forEach((m, i) => { if (m >= a && m <= b && (best === null || m1.pc[i] > m1.pc[best])) best = i; }); return best; };
    const rows = [['1982/83 El Nino', '1982-06', '1983-06'], ['1997/98 El Nino', '1997-06', '1998-06'], ['2015/16 El Nino', '2015-06', '2016-06'], ['2023/24 El Nino', '2023-04', '2024-04'], ['2026 El Nino', '2026-01', '2026-12']]
      .filter(([lab, a, b]) => a >= E.months[0] && a <= E.months[E.months.length - 1])
      .map(([lab, a, b]) => { const i = peak(a, b); return '<tr><td>' + lab + '</td><td class="mono">' + E.months[i] + '</td><td class="mono">' + m1.pc[i].toFixed(2) + ' sd</td></tr>'; }).join('');
    $('checks').innerHTML =
      '<p>' + (CFG.mode1 ? 'Mode 1 is ENSO: its' : 'Mode 1\'s') + ' time series correlates ' + m1.r_nino34_box.toFixed(2) +
      ' with the Nino 3.4 box anomaly' + (CFG.mode1 ? ', and ' + CFG.mode1 : '') + '. Its peaks in each El Nino window:</p>' +
      '<table style="border-collapse:collapse;font-size:13px">' + rows + '</table>' +
      (CFG.oni ? '<p>' + CFG.oni + '</p>' : '') +
      '<p>Masked: ' + (E.masked.filter(x => x.cells > 0).map(x => x.label + ' (' + x.cells + ' cells)').join(', ') || 'none') + '.</p>' +
      '<p class="mono" style="font-size:12px;color:var(--text-muted)">' + E.cells_used + ' cells x ' + E.months.length + ' months, ' + E.months[0] + ' to ' + E.months[E.months.length - 1] + '; ' + E.method + '.</p>';
  }

  fetch('data/coast-110m.json').then(r => r.json()).catch(() => null).then(k => { coast = k; load(src); });
  function load(id) {
    src = id;
    Promise.all([fetch('data/eof-' + id + '.json').then(r => r.json()), fetch('data/cells-' + id + '.json').then(r => r.json())])
      .then(([e, c]) => {
        E = e; C = c;
        if (sel >= E.modes.length) sel = 0;
        $('modes').innerHTML = E.modes.map((m, i) => '<button type="button">Mode ' + m.mode + ' <span style="color:var(--text-muted)">' + (100 * m.variance).toFixed(1) + '%</span></button>').join('');
        document.querySelectorAll('#modes button').forEach((b, i) => b.addEventListener('click', () => { sel = i; draw(); }));
        document.querySelectorAll('#srcs button').forEach(b => b.classList.toggle('on', b.dataset.id === id));
        checks(); draw();
      });
  }
  if (CFG.sources.length > 1) {
    $('srcs').hidden = false;
    $('srcs').innerHTML = CFG.sources.map(x => '<button type="button" data-id="' + x.id + '">' + x.label + '</button>').join('');
    document.querySelectorAll('#srcs button').forEach(b => b.addEventListener('click', () => load(b.dataset.id)));
  }
  let rt; window.addEventListener('resize', () => { clearTimeout(rt); rt = setTimeout(() => E && draw(), 150); });
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => E && draw());
})();
