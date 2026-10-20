// Croix occitane (12 pommettes) dans le style du blason d'origine :
// or uni, léger relief, ombre portée bleu nuit vers le bas à droite.
// Usage : node cross.js cx cy D rotationDeg largeur hauteur > cross.svg
const { crossPath2D, f } = require('./geo');
const [cx, cy, D, rot, W, H] = process.argv.slice(2).map(Number);
const { band, pommels } = crossPath2D(D);
const thick = 0.085 * D; // épaissit le trait pour retrouver la croix plus massive du blason
const shape = (fill) =>
  `<path d="${band}" fill="${fill}" fill-rule="evenodd" stroke="${fill}" stroke-width="${f(thick)}" stroke-linejoin="round"/>` +
  pommels.map((p) => `<circle cx="${p.cx}" cy="${p.cy}" r="${f(D * 0.1)}" fill="${fill}"/>`).join('');
process.stdout.write(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">
<defs>
  <filter id="sh" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="${f(D * 0.012)}"/></filter>
  <filter id="bevel" x="-10%" y="-10%" width="120%" height="120%">
    <feGaussianBlur in="SourceAlpha" stdDeviation="${f(D * 0.018)}" result="b"/>
    <feSpecularLighting in="b" surfaceScale="2.2" specularConstant="0.55" specularExponent="16" lighting-color="#FFF1C9" result="s"><feDistantLight azimuth="225" elevation="52"/></feSpecularLighting>
    <feComposite in="s" in2="SourceAlpha" operator="in" result="si"/>
    <feComposite in="SourceGraphic" in2="si" operator="arithmetic" k1="0" k2="1" k3="0.35" k4="0"/>
  </filter>
</defs>
<g transform="translate(${cx} ${cy}) rotate(${rot})">
  <g transform="rotate(${-rot}) translate(${f(D * 0.026)} ${f(D * 0.034)}) rotate(${rot})" filter="url(#sh)">${shape('#030F3A')}</g>
  <g transform="rotate(${-rot}) translate(${f(D * 0.01)} ${f(D * 0.014)}) rotate(${rot})">${shape('#A8822F')}</g>
  <g filter="url(#bevel)">${shape('#D9B24A')}</g>
</g></svg>`);
