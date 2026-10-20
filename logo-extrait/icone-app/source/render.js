// Usage : node render.js in.svg out.png size
const { chromium } = require('playwright');
const path = require('path');
(async () => {
  const [inSvg, outPng, size] = process.argv.slice(2);
  const px = Number(size);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: px, height: px } });
  const html = `<html><body style="margin:0"><div style="width:${px}px;height:${px}px">${require('fs').readFileSync(inSvg,'utf8').replace(/width="\d+" height="\d+"/, 'width="'+px+'" height="'+px+'"')}</div></body></html>`;
  const tmp = path.resolve(inSvg) + '.html';
  require('fs').writeFileSync(tmp, html);
  await page.goto('file://' + tmp);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(300);
  await page.screenshot({ path: outPng, omitBackground: true });
  await browser.close();
})();
