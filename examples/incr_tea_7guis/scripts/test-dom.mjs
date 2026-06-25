import { chromium } from 'playwright';
import { createServer } from 'node:http';
import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const distRoot = resolve(fileURLToPath(new URL('../dist/', import.meta.url)));
const host = '127.0.0.1';

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function contentType(filePath) {
  switch (extname(filePath)) {
    case '.html':
      return 'text/html; charset=utf-8';
    case '.js':
      return 'text/javascript; charset=utf-8';
    case '.css':
      return 'text/css; charset=utf-8';
    default:
      return 'application/octet-stream';
  }
}

function filePathForRequest(pathname) {
  const localPath = pathname === '/' ? '/index.html' : decodeURIComponent(pathname);
  const filePath = resolve(distRoot, `.${localPath}`);
  assert(
    filePath === distRoot || filePath.startsWith(`${distRoot}${sep}`),
    `Refusing to serve path outside dist: ${pathname}`,
  );
  return filePath;
}

const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url ?? '/', `http://${request.headers.host ?? host}`);
    const filePath = filePathForRequest(url.pathname);
    const bytes = await readFile(filePath);
    response.writeHead(200, { 'content-type': contentType(filePath) });
    response.end(bytes);
  } catch (error) {
    response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    response.end(error instanceof Error ? error.message : 'not found');
  }
});

await new Promise((resolve, reject) => {
  server.once('error', reject);
  server.listen(0, host, resolve);
});

let browser;
try {
  const address = server.address();
  assert(address && typeof address === 'object', 'DOM test server did not bind to a TCP port');
  const baseUrl = `http://${host}:${address.port}`;

  const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ??
    (existsSync('/usr/bin/google-chrome') ? '/usr/bin/google-chrome' : undefined);
  browser = await chromium.launch({ executablePath, headless: process.env.HEADLESS !== '0' });
  const page = await browser.newPage();
  const pageErrors = [];
  page.on('pageerror', error => pageErrors.push(error));

  await page.goto(`${baseUrl}/`, { waitUntil: 'load' });
  await page.waitForSelector('#counter-root .counter-readout');

  const titles = await page.locator('.task-card h2').allTextContents();
  assert(
    ['Counter', 'Temperature Converter', 'Flight Booker', 'Timer', 'CRUD', 'Circle Drawer', 'Cells', 'Keyboard Shortcut']
      .every(title => titles.includes(title)),
    `Expected all 7GUIs task roots to mount, got: ${titles.join(', ')}`,
  );

  await page.locator('#counter-root button', { hasText: 'Count' }).click();
  await page.waitForFunction(() => document.querySelector('#counter-root .counter-readout')?.textContent?.trim() === '1');

  const board = page.locator('#circle-root .circle-board');
  const box = await board.boundingBox();
  assert(box, 'Circle board did not render');
  await board.click({ position: { x: 40, y: 45 } });
  await page.waitForSelector('#circle-root .circle');
  const clickedBox = await board.boundingBox();
  assert(clickedBox, 'Circle board disappeared after click');
  const circleBox = await page.locator('#circle-root .circle').boundingBox();
  assert(circleBox, 'Circle did not render after click');
  assert(
    Math.abs((circleBox.x + circleBox.width / 2) - (clickedBox.x + 40)) < 4,
    `Circle x was not board-local: board=${clickedBox.x}, circle=${circleBox.x}`,
  );
  assert(
    Math.abs((circleBox.y + circleBox.height / 2) - (clickedBox.y + 45)) < 4,
    `Circle y was not board-local: board=${clickedBox.y}, circle=${circleBox.y}`,
  );

  await page.locator('#flight-kind').selectOption('return');
  await page.waitForFunction(() => !document.querySelector('#flight-return')?.disabled);
  await page.locator('#flight-start').fill('2026-06-17');
  await page.locator('#flight-return').fill('2026-06-19');
  await page.locator('#flight-root button', { hasText: 'Book' }).click();
  await page.waitForFunction(() =>
    document.querySelector('#flight-root .status')?.textContent?.trim() ===
      'Booked return flight from 2026-06-17 to 2026-06-19.',
  );

  // Keyboard shortcut: verify window keydown listener starts, dispatches, pauses, and resumes
  await page.waitForSelector('#keyboard-shortcut-root .counter-readout');
  assert(
    (await page.locator('#keyboard-shortcut-root .counter-readout').textContent())?.trim() === '0',
    'Keyboard shortcut counter should start at 0',
  );
  // Click the section to ensure the page (not an input) has focus before key presses
  await page.locator('#keyboard-shortcut-root .counter-readout').click();
  await page.keyboard.press('k');
  await page.waitForFunction(
    () => document.querySelector('#keyboard-shortcut-root .counter-readout')?.textContent?.trim() === '1',
  );
  await page.keyboard.press('k');
  await page.waitForFunction(
    () => document.querySelector('#keyboard-shortcut-root .counter-readout')?.textContent?.trim() === '2',
  );
  // Pause: listener should be removed; further key presses must not increment
  await page.locator('#keyboard-shortcut-root button', { hasText: 'Pause' }).click();
  await page.waitForFunction(
    () => document.querySelector('#keyboard-shortcut-root .status')?.textContent?.trim() === 'Paused',
  );
  await page.keyboard.press('k');
  // Wait one rAF so any renderer flush that would follow an erroneous dispatch has time to run
  await page.evaluate(() => new Promise(r => requestAnimationFrame(r)));
  assert(
    (await page.locator('#keyboard-shortcut-root .counter-readout').textContent())?.trim() === '2',
    'Counter must not increment while paused',
  );
  // Resume: listener restarts; next key press should increment again
  await page.locator('#keyboard-shortcut-root button', { hasText: 'Resume' }).click();
  await page.waitForFunction(
    () => document.querySelector('#keyboard-shortcut-root .status')?.textContent?.trim() === 'Listening — press k',
  );
  await page.keyboard.press('k');
  await page.waitForFunction(
    () => document.querySelector('#keyboard-shortcut-root .counter-readout')?.textContent?.trim() === '3',
  );

  assert(pageErrors.length === 0, `Page errors: ${pageErrors.map(error => error.message).join('\n')}`);
  console.log(`DOM check passed for ${baseUrl}/`);
} finally {
  if (browser) await browser.close();
  await new Promise(resolve => server.close(resolve));
}
