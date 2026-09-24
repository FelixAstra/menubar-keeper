#!/usr/bin/env node
/**
 * Renders the MenuBarKeeper desktop simulation to PNG frames.
 *
 *   node render.mjs <outDir> [--fps 20] [--duration 13400] [--scale 2]
 *                             [--width 1280] [--height 800]
 *                             [--times 0,500,1000]   (ad-hoc frames instead of a range)
 *                             [--query cursor=0]     (extra page parameters, e.g. hide the pointer)
 *
 * The page renders a pure *function of time* (`index.html?t=<ms>`), so a frame can be
 * produced on its own and re-produced identically later.
 *
 * One browser process drives every frame over CDP. That is both much faster than a
 * launch per frame and far more reliable: headless Chrome does not always exit on its
 * own when several instances run at once, and a reused `--user-data-dir` can serve a
 * stale document back to the next `--screenshot`.
 */
import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const argv = process.argv.slice(2);
const outDir = resolve(argv[0] ?? 'frames');
const flag = (name, def) => {
  const i = argv.indexOf('--' + name);
  return i === -1 ? def : argv[i + 1];
};

const fps = Number(flag('fps', 20));
const duration = Number(flag('duration', 13400));
const scale = Number(flag('scale', 2));
const width = Number(flag('width', 1280));
const height = Number(flag('height', 800));
const simDir = resolve(flag('sim', join(import.meta.dirname, 'sim')));
const page = flag('page', 'index.html');
const extraQuery = flag('query', '');

mkdirSync(outDir, { recursive: true });

const only = flag('times', null);
const times = only
  ? only.split(',').map(Number)
  : Array.from({ length: Math.round((duration / 1000) * fps) + 1 }, (_, i) => Math.round((i * 1000) / fps));

const browser = await chromium.launch({ executablePath: CHROME });
const context = await browser.newContext({
  viewport: { width, height },
  deviceScaleFactor: scale,
});
const tab = await context.newPage();

const problems = [];
tab.on('pageerror', (e) => problems.push(String(e.message)));
tab.on('console', (m) => { if (m.type() === 'error') problems.push(m.text()); });

const started = Date.now();
let done = 0;

for (const t of times) {
  await tab.goto('file://' + join(simDir, page) + '?t=' + t + (extraQuery ? '&' + extraQuery : ''), { waitUntil: 'load' });
  const state = await tab.evaluate(() => ({
    ready: document.documentElement.dataset.ready || '',
    error: document.documentElement.dataset.error || '',
  }));
  if (!state.ready || state.error) problems.push(`t=${t}: ${state.error || 'renderer did not finish'}`);

  await tab.screenshot({ path: join(outDir, 'f' + String(t).padStart(6, '0') + '.png') });
  if (++done % 25 === 0 || done === times.length) {
    const rate = done / ((Date.now() - started) / 1000);
    process.stdout.write(`  ${done}/${times.length} frames  (${rate.toFixed(1)} fps)\n`);
  }
}

await browser.close();

console.log(`rendered ${done} frames -> ${outDir} in ${((Date.now() - started) / 1000).toFixed(1)}s`);
if (problems.length) {
  console.error('problems:\n  ' + [...new Set(problems)].join('\n  '));
  process.exitCode = 1;
}
