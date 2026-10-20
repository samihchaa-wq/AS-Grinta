// Génère l'icône d'application AS La Grinta en SVG (plein cadre, sans bordure de blason).
// Usage : node make_svg.js <mode: any|maskable> <fontPath> > out.svg
const mode = process.argv[2] || 'any';
const fontPath = process.argv[3];
const S = 1024;

const BLUE_TOP = '#0733B4';
const BLUE_BOTTOM = '#04227F';
const GOLD = '#D9B24A';
const GOLD_DARK = '#A9832B';
const NAVY = '#030D31';
const WHITE = '#F4F6F9';

// En mode « maskable », Android peut rogner l'icône en cercle : on ramène
// le contenu dans la zone sûre (cercle de 80 %) tout en gardant le fond plein cadre.
const k = mode === 'maskable' ? 0.80 : 1;
const tr = (inner) =>
  `<g transform="translate(${S / 2} ${S / 2}) scale(${k}) translate(${-S / 2} ${-S / 2})">${inner}</g>`;

// ---------- Croix occitane (évidée, pommetée, 2 pommettes par branche comme l'original)
function occitanCross(cx, cy, size, rot) {
  const L = size / 2; // longueur d'une branche
  const tipX = 0.46 * L;
  const tipY = -0.98 * L;
  const arm = `M0 0 Q ${-0.06 * L} ${-0.55 * L} ${-tipX} ${tipY} Q 0 ${-0.74 * L} ${tipX} ${tipY} Q ${0.06 * L} ${-0.55 * L} 0 0 Z`;
  const sw = 0.12 * size;
  const r = 0.075 * size;
  let arms = '';
  for (let i = 0; i < 4; i++) {
    arms += `<g transform="rotate(${i * 90})">
      <path d="${arm}" fill="none" stroke="${GOLD}" stroke-width="${sw}" stroke-linejoin="round"/>
      <circle cx="${-tipX}" cy="${tipY}" r="${r}" fill="${GOLD}"/>
      <circle cx="${tipX}" cy="${tipY}" r="${r}" fill="${GOLD}"/>
    </g>`;
  }
  // ombre portée légère, comme le relief de l'original
  return `<g transform="translate(${cx} ${cy}) rotate(${rot})">
    <g transform="translate(${size * 0.018} ${size * 0.028})" opacity="0.45" style="filter:brightness(0)">${arms}</g>
    ${arms}
  </g>`;
}

// ---------- Ballon (icosaèdre tronqué projeté sur la sphère : vrai motif de ballon)
function ball(cx, cy, R, tiltX = -18, tiltY = 12, spin = 8) {
  const phi = (1 + Math.sqrt(5)) / 2;
  const V = [];
  for (const a of [-1, 1]) for (const b of [-phi, phi]) {
    V.push([0, a, b], [a, b, 0], [b, 0, a]);
  }
  const norm = (p) => { const l = Math.hypot(...p); return p.map((c) => c / l); };
  const lerp = (p, q, t) => p.map((c, i) => c + (q[i] - c) * t);
  const dist = (p, q) => Math.hypot(...p.map((c, i) => c - q[i]));
  const edgeLen = 2;
  const nbrs = V.map((v, i) => V.map((u, j) => j).filter((j) => j !== i && Math.abs(dist(v, V[j]) - edgeLen) < 1e-6));
  // rotation : un pentagone face à nous, puis légère inclinaison
  const rot = (p) => {
    let [x, y, z] = p;
    // aligner V[0]=(0,-1,-phi) sur l'axe z
    const v0 = norm(V[2 * 0 + 0]);
    const ang = Math.atan2(v0[1], -v0[2]);
    let c = Math.cos(ang), s = Math.sin(ang);
    [y, z] = [y * c + z * s * -1 * -1, -y * s + z * c];
    const r = (deg) => (deg * Math.PI) / 180;
    // inclinaisons
    c = Math.cos(r(tiltX)); s = Math.sin(r(tiltX)); [y, z] = [y * c - z * s, y * s + z * c];
    c = Math.cos(r(tiltY)); s = Math.sin(r(tiltY)); [x, z] = [x * c + z * s, -x * s + z * c];
    c = Math.cos(r(spin)); s = Math.sin(r(spin)); [x, y] = [x * c - y * s, x * s + y * c];
    return [x, y, z];
  };
  const faces = [];
  // pentagones
  V.forEach((v, i) => {
    const pts = nbrs[i].map((j) => lerp(v, V[j], 1 / 3));
    faces.push({ pts, dark: true });
  });
  // hexagones
  for (let i = 0; i < 12; i++) for (const j of nbrs[i]) for (const k2 of nbrs[i]) {
    if (!(i < j && j < k2)) continue;
    if (!nbrs[j].includes(k2)) continue;
    const [a, b, c] = [V[i], V[j], V[k2]];
    faces.push({ pts: [lerp(a, b, 1 / 3), lerp(a, b, 2 / 3), lerp(b, c, 1 / 3), lerp(b, c, 2 / 3), lerp(c, a, 1 / 3), lerp(c, a, 2 / 3)], dark: false });
  }
  let out = '';
  for (const f of faces) {
    const center = norm(f.pts.reduce((acc, p) => acc.map((c, i) => c + p[i]), [0, 0, 0]));
    // ordonner les sommets autour du centre
    const ref = norm(f.pts[0].map((c, i) => c - center[i] * 0));
    const u = norm(f.pts[0].map((c, i) => c - center[i] * f.pts[0].reduce((s2, cc, ii) => s2 + cc * center[ii], 0)));
    const w = [center[1] * u[2] - center[2] * u[1], center[2] * u[0] - center[0] * u[2], center[0] * u[1] - center[1] * u[0]];
    f.pts.sort((p, q) => Math.atan2(p.reduce((s2, c, i) => s2 + c * w[i], 0), p.reduce((s2, c, i) => s2 + c * u[i], 0)) - Math.atan2(q.reduce((s2, c, i) => s2 + c * w[i], 0), q.reduce((s2, c, i) => s2 + c * u[i], 0)));
    const rc = rot(center);
    
    // contour échantillonné sur la sphère (arêtes courbes)
    const poly = [];
    const n2 = f.pts.length;
    for (let e = 0; e < n2; e++) {
      const p = f.pts[e], q = f.pts[(e + 1) % n2];
      for (let t = 0; t < 16; t++) poly.push(rot(norm(lerp(p, q, t / 16))));
    }
    if (Math.max(...poly.map((p) => p[2])) <= 0) continue;
    for (const p of poly) if (p[2] < 0) { const l = Math.hypot(p[0], p[1]); p[0] /= l; p[1] /= l; p[2] = 0; }
    const d = poly.map((p, idx) => `${idx ? 'L' : 'M'}${(p[0] * R).toFixed(1)} ${(-p[1] * R).toFixed(1)}`).join(' ') + 'Z';
    f.d = d; f.z = rc[2];
    out += '';
    f.visible = true;
  }
  const vis = faces.filter((f) => f.visible).sort((a, b) => a.z - b.z);
  out = vis.map((f) => `<path d="${f.d}" fill="${f.dark ? NAVY : 'none'}" stroke="${NAVY}" stroke-width="${R * 0.022}" stroke-linejoin="round"/>`).join('');
  return `<g transform="translate(${cx} ${cy})">
    <circle r="${R * 1.07}" fill="${WHITE}"/>
    <circle r="${R}" fill="url(#ballShade)"/>
    <g clip-path="url(#ballClip)">${out}<circle r="${R}" fill="url(#ballShadow)"/><circle r="${R}" fill="url(#ballGloss)"/></g>
    <circle r="${R}" fill="none" stroke="${NAVY}" stroke-width="${R * 0.05}"/>
  </g>`;
}

// ---------- Mise en page
const bandTop = 318;
const bandH = 150;
const arch = 26; // courbure de la banderole (bord haut et bas légèrement cintrés)
const stripeTop = bandTop + bandH - 20;

const stripes = [];
const n = 7;
const w = S / n;
for (let i = 1; i < n; i += 2) {
  stripes.push(`<rect x="${(i * w).toFixed(1)}" y="${stripeTop}" width="${w.toFixed(1)}" height="${S - stripeTop + 200}" fill="${GOLD}"/>`);
}

const bandPath = (top, h) =>
  `M -200 ${top + arch} Q ${S / 2} ${top - arch} ${S + 200} ${top + arch} L ${S + 200} ${top + h + arch} Q ${S / 2} ${top + h - arch} -200 ${top + h + arch} Z`;

const content = `
  ${stripes.join('\n')}
  ${occitanCross(730, 168, 240, 18)}
  <path d="${bandPath(bandTop + 10, bandH)}" fill="${NAVY}" opacity="0.35"/>
  <path d="${bandPath(bandTop, bandH)}" fill="url(#bandShade)"/>
  <path id="textArc" d="M -40 ${bandTop + bandH / 2 + 52} Q ${S / 2} ${bandTop + bandH / 2 + 52 - 2 * arch} ${S + 40} ${bandTop + bandH / 2 + 52}" fill="none"/>
  <text font-family="Grinta" font-weight="700" font-size="128" fill="${NAVY}" letter-spacing="4" text-anchor="middle">
    <textPath href="#textArc" startOffset="50%">AS LA GRINTA</textPath>
  </text>
  <text x="${S / 2}" y="${stripeTop + 92}" font-family="Grinta" font-weight="700" font-size="74" fill="${NAVY}" text-anchor="middle" letter-spacing="3">2020</text>
  ${ball(S / 2, 838, 268)}
`;

const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${S} ${S}" width="${S}" height="${S}">
  <defs>
    <style>@font-face{font-family:Grinta;font-weight:700;src:url('file://${fontPath}')}</style>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${BLUE_TOP}"/><stop offset="1" stop-color="${BLUE_BOTTOM}"/>
    </linearGradient>
    <linearGradient id="bandShade" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/><stop offset="0.75" stop-color="${WHITE}"/><stop offset="1" stop-color="#D5DBE5"/>
    </linearGradient>
    <radialGradient id="ballShade" cx="0.38" cy="0.32" r="0.8">
      <stop offset="0" stop-color="#FFFFFF"/><stop offset="0.7" stop-color="#ECEFF4"/><stop offset="1" stop-color="#B9C2D2"/>
    </radialGradient>
    <radialGradient id="ballGloss" cx="0.35" cy="0.25" r="0.7">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.18"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="ballShadow" cx="0.4" cy="0.35" r="0.75">
      <stop offset="0.55" stop-color="${NAVY}" stop-opacity="0"/><stop offset="1" stop-color="${NAVY}" stop-opacity="0.45"/>
    </radialGradient>
    <clipPath id="ballClip"><circle r="268"/></clipPath>
  </defs>
  <rect width="${S}" height="${S}" fill="url(#bg)"/>
  ${tr(content)}
</svg>`;

process.stdout.write(svg);
