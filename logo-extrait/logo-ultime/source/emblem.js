// Emblème « ballon occitan » : la croix occitane épouse la surface du ballon.
const { f, norm, dot, crossPolygons, ballFaces, makeRotation } = require('./geo');

function emblem({ R, thetaMax = 58, tilt = [['x', 12], ['y', -14]], ballSpin = [['x', -8], ['y', 22], ['z', 6]], id = 'e', shadow = 0.6 }) {
  const rad = (d) => (d * Math.PI) / 180;
  const Rmax = 1.14;
  const crossRot = makeRotation([0, 0, 1], tilt);
  const toSphere = ([px, py]) => {
    const r = Math.hypot(px, py) / Rmax;
    const th = r * rad(thetaMax);
    const ph = Math.atan2(py, px);
    return crossRot([Math.sin(th) * Math.cos(ph), -Math.sin(th) * Math.sin(ph), Math.cos(th)]);
  };
  const proj = (p) => `${f(p[0] * R)} ${f(-p[1] * R)}`;
  const polyD = (poly) => poly.map((p, i) => `${i ? 'L' : 'M'}${proj(p)}`).join('') + 'Z';

  const { outer, inner, pommels } = crossPolygons();
  const crossD = `${polyD(outer.map(toSphere))} ${polyD(inner.map(toSphere))}`;
  const pommelD = pommels.map((p) => polyD(p.poly.map(toSphere))).join(' ');

  // panneaux du ballon (discrets, sous la croix)
  const { faces } = ballFaces();
  const rot = makeRotation([0, 1, 1.618], ballSpin);
  let panels = '';
  for (const face of faces) {
    const poly = [];
    const n = face.pts.length;
    for (let e = 0; e < n; e++) {
      const p = face.pts[e], q = face.pts[(e + 1) % n];
      for (let t = 0; t < 12; t++) poly.push(rot(norm(p.map((c, i) => c + (q[i] - c) * (t / 12)))));
    }
    if (Math.max(...poly.map((p) => p[2])) <= 0) continue;
    for (const p of poly) if (p[2] < 0) {
      const l = Math.hypot(p[0], p[1]);
      p[0] /= l; p[1] /= l; p[2] = 0;
    }
    panels += `<path d="${polyD(poly)}" fill="${face.pent ? `url(#${id}pent)` : 'none'}" stroke="#AEB9CC" stroke-width="${f(R * 0.012)}" stroke-linejoin="round"/>`;
  }

  const defs = `
    <radialGradient id="${id}white" cx="0.36" cy="0.3" r="0.85">
      <stop offset="0" stop-color="#FFFFFF"/><stop offset="0.55" stop-color="#F1F4F9"/><stop offset="0.85" stop-color="#C9D2E2"/><stop offset="1" stop-color="#8E9BB4"/>
    </radialGradient>
    <radialGradient id="${id}pent" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#D9E0EC"/><stop offset="1" stop-color="#C5CFDF"/></radialGradient>
    <linearGradient id="${id}gold" x1="${f(-R * 0.9)}" y1="${f(-R * 0.9)}" x2="${f(R * 0.8)}" y2="${f(R * 0.9)}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFF1BE"/><stop offset="0.2" stop-color="#F6CD62"/><stop offset="0.42" stop-color="#C8912A"/><stop offset="0.56" stop-color="#EDC060"/><stop offset="0.8" stop-color="#B57D1F"/><stop offset="1" stop-color="#7C5311"/>
    </linearGradient>
    <filter id="${id}bevel" x="-10%" y="-10%" width="120%" height="120%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="${f(R * 0.008)}" result="b"/>
      <feSpecularLighting in="b" surfaceScale="3" specularConstant="0.9" specularExponent="22" lighting-color="#FFF5D6" result="s"><feDistantLight azimuth="225" elevation="50"/></feSpecularLighting>
      <feComposite in="s" in2="SourceAlpha" operator="in" result="si"/>
      <feComposite in="SourceGraphic" in2="si" operator="arithmetic" k1="0" k2="1" k3="0.4" k4="0"/>
    </filter>
    <radialGradient id="${id}rim" cx="0.42" cy="0.38" r="0.7">
      <stop offset="0.62" stop-color="#061647" stop-opacity="0"/><stop offset="1" stop-color="#061647" stop-opacity="0.45"/>
    </radialGradient>
    <radialGradient id="${id}spec" cx="0.32" cy="0.26" r="0.3">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.6"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <clipPath id="${id}clip"><circle r="${R}"/></clipPath>
    <filter id="${id}shadow" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="${f(R * 0.06)}"/></filter>
    <filter id="${id}crossShadow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="${f(R * 0.012)}"/></filter>`;

  const body = `
    <ellipse cx="${f(R * 0.04)}" cy="${f(R * 0.12)}" rx="${f(R * 1.02)}" ry="${f(R * 1.02)}" fill="#020A2A" opacity="${shadow}" filter="url(#${id}shadow)"/>
    <g clip-path="url(#${id}clip)">
      <circle r="${R}" fill="url(#${id}white)"/>
      ${panels}
      <g filter="url(#${id}crossShadow)" opacity="0.45" transform="translate(${f(R * 0.012)} ${f(R * 0.024)})">
        <path d="${crossD}" fill="#0A1540" fill-rule="evenodd" stroke="#0A1540" stroke-width="${f(R * 0.05)}"/><path d="${pommelD}" fill="#0A1540" stroke="#0A1540" stroke-width="${f(R * 0.03)}"/>
      </g>
      <path d="${crossD}" fill="none" stroke="#5A3C08" stroke-width="${f(R * 0.042)}" stroke-linejoin="round"/>
      <path d="${pommelD}" fill="#5A3C08" stroke="#5A3C08" stroke-width="${f(R * 0.026)}"/>
      <g filter="url(#${id}bevel)"><path d="${crossD}" fill="url(#${id}gold)" fill-rule="evenodd" stroke="url(#${id}gold)" stroke-width="${f(R * 0.03)}" stroke-linejoin="round"/>
      <path d="${pommelD}" fill="url(#${id}gold)" stroke="url(#${id}gold)" stroke-width="${f(R * 0.014)}"/></g>
      <circle r="${R}" fill="url(#${id}rim)"/>
      <circle r="${R}" fill="url(#${id}spec)"/>
    </g>
    <circle r="${R}" fill="none" stroke="#06103A" stroke-width="${f(R * 0.018)}"/>`;
  return { defs, body };
}

module.exports = { emblem };
