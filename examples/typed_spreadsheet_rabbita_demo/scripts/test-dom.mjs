import { chromium } from 'playwright';
import { createServer } from 'node:http';
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

async function waitForCellText(page, cell, expected) {
  await page.waitForFunction(({ id, text }) => {
    const element = document.getElementById(id);
    return element?.textContent?.trim() === text;
  }, { id: `cell-${cell}`, text: expected });
}

async function runTest(name, fn) {
  await fn();
  console.log(`✓ ${name}`);
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

  browser = await chromium.launch({ headless: process.env.HEADLESS !== '0' });
  const page = await browser.newPage();
  const pageErrors = [];
  page.on('pageerror', error => pageErrors.push(error));

  await page.goto(`${baseUrl}/`, { waitUntil: 'load' });
  await page.waitForSelector('#cell-B1');
  await waitForCellText(page, 'B1', '11');

  const toggle = page.getByRole('button', { name: 'Toggle explain inspector' });
  const inspector = page.getByRole('complementary', { name: /^Explanation for / });

  await runTest('explanation inspector is initially hidden', async () => {
    assert(await inspector.count() === 0, 'explanation inspector should start closed');
    assert(await toggle.getAttribute('aria-pressed') === 'false', 'explanation toggle should start unpressed');
  });

  await runTest('explain B1 shows its value and active input', async () => {
    await toggle.click();
    const b1Inspector = page.getByRole('complementary', { name: 'Explanation for B1' });
    await b1Inspector.waitFor();
    assert(await toggle.getAttribute('aria-pressed') === 'true', 'explanation toggle should expose its expanded state');
    assert(await b1Inspector.getByRole('heading', { name: 'B1', exact: true }).count() === 1, 'B1 heading missing');
    assert(await b1Inspector.locator('.explanation-result').textContent() === '11', 'expected B1 result 11');
    const input = b1Inspector.getByRole('button', { name: 'Select input A1' });
    assert(await input.count() === 1, 'expected active input A1');
    assert(await input.locator('strong').textContent() === '10', 'expected active input A1 = 10');
  });

  await runTest('open explanation follows an empty-cell selection', async () => {
    await page.locator('#cell-C1').click();
    const emptyInspector = page.getByRole('complementary', { name: 'Explanation for C1' });
    await emptyInspector.waitFor();
    assert(
      await emptyInspector.locator('.explanation-result').textContent() === 'Empty cell',
      'expected selected empty cell result',
    );
  });

  await runTest('editing B1 refreshes result and before/after evidence', async () => {
    await page.locator('#cell-B1').dblclick();
    const editor = page.locator('#inline-editor-B1');
    await editor.waitFor();
    await editor.fill('=A1 + 2');
    await page.keyboard.press('Enter');
    await editor.waitFor({ state: 'detached' });
    await waitForCellText(page, 'B1', '12');

    const b1Inspector = page.getByRole('complementary', { name: 'Explanation for B1' });
    await b1Inspector.waitFor();
    assert(await b1Inspector.locator('.explanation-result').textContent() === '12', 'expected updated B1 result 12');
    assert(await b1Inspector.locator('.explanation-formula').textContent() === '=A1 + 2', 'expected updated B1 formula');

    const beforeAfter = b1Inspector.locator('.explanation-before-after');
    assert(await beforeAfter.locator('div').first().locator('strong').textContent() === '11', 'expected before result 11');
    assert(await beforeAfter.locator('div').last().locator('strong').textContent() === '12', 'expected after result 12');
  });

  await runTest('keyboard reaches native trace disclosure with a visible focus outline', async () => {
    const b1Inspector = page.getByRole('complementary', { name: 'Explanation for B1' });
    await b1Inspector.getByRole('button', { name: 'Select input A1' }).focus();
    await page.keyboard.press('Tab');

    const disclosure = b1Inspector.locator('.explanation-history details');
    const summary = disclosure.locator('summary');
    assert(
      await summary.evaluate(element => document.activeElement === element),
      'expected keyboard focus to reach the trace disclosure',
    );
    const focusStyle = await summary.evaluate(element => {
      const style = getComputedStyle(element);
      return {
        display: style.display,
        outlineStyle: style.outlineStyle,
        outlineWidth: style.outlineWidth,
      };
    });
    assert(focusStyle.display === 'list-item', `expected native disclosure marker, got ${focusStyle.display}`);
    assert(
      focusStyle.outlineStyle !== 'none' && Number.parseFloat(focusStyle.outlineWidth) > 0,
      `expected visible keyboard focus outline, got ${JSON.stringify(focusStyle)}`,
    );

    await page.keyboard.press('Enter');
    await page.waitForFunction(() => document.querySelector('.explanation-history details')?.open === true);
    assert(
      await b1Inspector.locator('.explanation-before-after').isVisible(),
      'before/after evidence should be visible after expanding the disclosure',
    );
    assert(
      await b1Inspector.getByRole('button', { name: 'Select cell B1 from Recomputed trace bucket' }).count() === 1,
      'recomputed trace bucket should include B1',
    );
    assert(
      await b1Inspector.getByRole('button', { name: 'Select cell B1 from Changed trace bucket' }).count() === 1,
      'changed trace bucket should include B1',
    );
  });

  assert(pageErrors.length === 0, `Page errors: ${pageErrors.map(error => error.message).join('\n')}`);
} finally {
  if (browser) await browser.close();
  await new Promise(resolve => server.close(resolve));
}
