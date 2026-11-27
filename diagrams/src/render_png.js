const { chromium } = require('playwright');
(async () => {
  const [,, svg, png, scale] = process.argv;
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1900, height: 1460 }, deviceScaleFactor: Number(scale || 1) });
  await p.goto('file://' + svg);
  await p.screenshot({ path: png, fullPage: false });
  await b.close();
})();
