// Usage : node render.js in.svg out.png largeur [hauteur]
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
(async () => {
  const [inSvg, outPng, w, h] = process.argv.slice(2);
  const width = Number(w);
  const height = Number(h || w);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width, height } });
  const svg = fs.readFileSync(inSvg, 'utf8').replace(/width="\d+" height="\d+"/, `width="${width}" height="${height}"`);
  const tmp = path.resolve(outPng) + '.tmp.html';
  fs.writeFileSync(tmp, `<html><body style="margin:0">${svg}</body></html>`);
  await page.goto('file://' + tmp);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(300);
  await page.screenshot({ path: outPng, omitBackground: true });
  fs.unlinkSync(tmp);
  await browser.close();
})();
