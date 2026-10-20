// Géométrie partagée : croix occitane (12 pommettes) et ballon (icosaèdre tronqué).
const f = (n) => Number(n.toFixed(2));
const norm = (p) => {
  const l = Math.hypot(...p);
  return p.map((c) => c / l);
};
const lerp = (p, q, t) => p.map((c, i) => c + (q[i] - c) * t);
const dot = (a, b) => a.reduce((s, c, i) => s + c * b[i], 0);

// ---- Croix occitane, unités : D = 1 (centre → pointe centrale d'une branche)
const OUTER_HALF = [
  ['C', [-0.202, -0.444], [-0.351, -0.639], [-0.408, -0.696]],
  ['L', [-0.442, -0.741]],
  ['L', [-0.391, -0.749]],
  ['C', [-0.2, -0.779], [-0.087, -0.89], [-0.033, -0.958]],
  ['L', [0, -1.0]],
];
const OUTER_JOIN = [-0.161, -0.161];
const INNER_HALF = [
  ['C', [-0.058, -0.197], [-0.094, -0.49], [-0.252, -0.679]],
  ['C', [-0.252, -0.679], [-0.12, -0.708], [0, -0.837]],
];
const INNER_JOIN = [-0.05, -0.05];
const POMMELS = [[0, -1.041], [-0.47, -0.775], [0.47, -0.775]];
const POMMEL_R = 0.096;

const turn = (pt, k) => {
  let [x, y] = pt;
  for (let i = 0; i < k; i++) [x, y] = [-y, x];
  return [x, y];
};
const mirror = ([x, y]) => [-x, y];

function armSegments(half, join) {
  const pts = [join, ...half.map((h) => h[h.length - 1])];
  const segs = half.map((h) => h.slice());
  for (let i = half.length - 1; i >= 0; i--) {
    const [cmd, ...ps] = half[i];
    const start = mirror(pts[i]);
    if (cmd === 'C') segs.push(['C', mirror(ps[1]), mirror(ps[0]), start]);
    else segs.push(['L', start]);
  }
  return segs;
}

// Contour échantillonné (liste de points) d'une boucle complète de la croix.
function sampleLoop(half, join, steps = 24) {
  const out = [join];
  let cur = join;
  for (let k = 0; k < 4; k++) {
    for (const [cmd, ...ps] of armSegments(half, join)) {
      const q = ps.map((p) => turn(p, k));
      if (cmd === 'L') {
        for (let t = 1; t <= 4; t++) out.push(lerp(cur, q[0], t / 4));
        cur = q[0];
      } else {
        const [c1, c2, e] = q;
        for (let t = 1; t <= steps; t++) {
          const u = t / steps, m = 1 - u;
          out.push([
            m * m * m * cur[0] + 3 * m * m * u * c1[0] + 3 * m * u * u * c2[0] + u * u * u * e[0],
            m * m * m * cur[1] + 3 * m * m * u * c1[1] + 3 * m * u * u * c2[1] + u * u * u * e[1],
          ]);
        }
        cur = e;
      }
    }
  }
  return out;
}

function crossPolygons() {
  const outer = sampleLoop(OUTER_HALF, OUTER_JOIN);
  const inner = sampleLoop(INNER_HALF, INNER_JOIN);
  const pommels = [];
  for (let k = 0; k < 4; k++)
    for (const p of POMMELS) {
      const c = turn(p, k);
      const poly = [];
      for (let i = 0; i < 40; i++) {
        const a = (i / 40) * Math.PI * 2;
        poly.push([c[0] + POMMEL_R * Math.cos(a), c[1] + POMMEL_R * Math.sin(a)]);
      }
      pommels.push({ c, poly });
    }
  return { outer, inner, pommels };
}

// Croix plane en SVG (centre 0,0), D en pixels.
function crossPath2D(D) {
  const toD = (poly) => poly.map((p, i) => `${i ? 'L' : 'M'}${f(p[0] * D)} ${f(p[1] * D)}`).join('') + 'Z';
  const { outer, inner, pommels } = crossPolygons();
  return { band: `${toD(outer)} ${toD(inner)}`, pommels: pommels.map((p) => ({ cx: f(p.c[0] * D), cy: f(p.c[1] * D), r: f(POMMEL_R * D) })) };
}

// ---- Ballon : faces de l'icosaèdre tronqué sur la sphère unité
function ballFaces() {
  const phi = (1 + Math.sqrt(5)) / 2;
  const V = [];
  for (const a of [-1, 1]) for (const b of [-phi, phi]) V.push([0, a, b], [a, b, 0], [b, 0, a]);
  const near = (p, q) => Math.abs(Math.hypot(...p.map((c, i) => c - q[i])) - 2) < 1e-6;
  const nbrs = V.map((v, i) => V.map((_, j) => j).filter((j) => j !== i && near(v, V[j])));
  const faces = [];
  V.forEach((v, i) => faces.push({ pts: nbrs[i].map((j) => lerp(v, V[j], 1 / 3)), pent: true, center: norm(v) }));
  for (let i = 0; i < 12; i++)
    for (const j of nbrs[i])
      for (const k of nbrs[i]) {
        if (!(i < j && j < k) || !nbrs[j].includes(k)) continue;
        const [a, b, c] = [V[i], V[j], V[k]];
        faces.push({
          pts: [lerp(a, b, 1 / 3), lerp(a, b, 2 / 3), lerp(b, c, 1 / 3), lerp(b, c, 2 / 3), lerp(c, a, 1 / 3), lerp(c, a, 2 / 3)],
          pent: false,
          center: norm([a, b, c].reduce((s, p) => s.map((x, i) => x + p[i]), [0, 0, 0])),
        });
      }
  for (const face of faces) {
    const cen = face.center;
    const u = norm(face.pts[0].map((c, i) => c - cen[i] * dot(face.pts[0], cen)));
    const w = [cen[1] * u[2] - cen[2] * u[1], cen[2] * u[0] - cen[0] * u[2], cen[0] * u[1] - cen[1] * u[0]];
    const ang = (p) => Math.atan2(dot(p, w), dot(p, u));
    face.pts.sort((p, q) => ang(p) - ang(q));
  }
  return { faces, V };
}

// Rotation qui amène le vecteur « a » sur +z (vers l'observateur), puis inclinaisons.
function makeRotation(a, tilts) {
  a = norm(a);
  const rad = (d) => (d * Math.PI) / 180;
  const ay = Math.atan2(a[0], a[2]);
  const rotY = (p, t) => [p[0] * Math.cos(t) - p[2] * Math.sin(t), p[1], p[0] * Math.sin(t) + p[2] * Math.cos(t)];
  const rotX = (p, t) => [p[0], p[1] * Math.cos(t) - p[2] * Math.sin(t), p[1] * Math.sin(t) + p[2] * Math.cos(t)];
  const rotZ = (p, t) => [p[0] * Math.cos(t) - p[1] * Math.sin(t), p[0] * Math.sin(t) + p[1] * Math.cos(t), p[2]];
  const a1 = rotY(a, ay);
  const ax = -Math.atan2(a1[1], a1[2]);
  return (p) => {
    let q = rotX(rotY(p, ay), ax);
    for (const [axis, d] of tilts) {
      if (axis === 'x') q = rotX(q, rad(d));
      if (axis === 'y') q = rotY(q, rad(d));
      if (axis === 'z') q = rotZ(q, rad(d));
    }
    return q;
  };
}

module.exports = { f, norm, lerp, dot, crossPolygons, crossPath2D, ballFaces, makeRotation };
