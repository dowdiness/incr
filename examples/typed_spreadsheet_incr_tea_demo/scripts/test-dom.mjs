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
    const el = document.getElementById(id);
    return el?.textContent?.trim() === text;
  }, { id: `cell-${cell}`, text: expected });
}

async function activeInputState(page) {
  return page.evaluate(() => {
    const active = document.activeElement;
    return {
      id: active?.id ?? null,
      value: active instanceof HTMLInputElement ? active.value : null,
      selectionStart: active instanceof HTMLInputElement ? active.selectionStart : null,
      selectionEnd: active instanceof HTMLInputElement ? active.selectionEnd : null,
    };
  });
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
  await page.waitForSelector('#cell-AX50');
  const gridColumns = await page.locator('#sheet-grid').evaluate(element => {
    return getComputedStyle(element).gridTemplateColumns.trim().split(/\s+/).length;
  });
  assert(gridColumns === 51, `expected 50 spreadsheet columns plus row headers, got ${gridColumns}`);
  const initialContext = await page.evaluate(() => ({
    object: globalThis.typedSpreadsheetAIContext?.(),
    json: globalThis.typedSpreadsheetAIContextJson?.(),
  }));
  assert(initialContext.object?.schema_version === 1, 'initial AI context schema was not published');
  assert(typeof initialContext.json === 'string', 'initial AI context JSON was not published');
  assert(initialContext.object.selected_cell === 'B1', 'initial AI context selected cell mismatch');

  await runTest('focused grid keeps keyboard navigation across selection moves', async () => {
    await page.locator('#sheet-grid').focus();
    const anchor = await page.locator('#cell-C1').elementHandle();
    assert(anchor, 'C1 anchor missing before selection movement');
    await page.keyboard.press('ArrowLeft');
    await page.waitForFunction(() => document.querySelector('#sheet-grid')?.getAttribute('aria-activedescendant') === 'cell-A1');
    await page.keyboard.press('ArrowDown');
    await page.waitForFunction(() => document.querySelector('#sheet-grid')?.getAttribute('aria-activedescendant') === 'cell-A2');
    await page.keyboard.press('ArrowRight');
    await page.waitForFunction(() => document.querySelector('#sheet-grid')?.getAttribute('aria-activedescendant') === 'cell-B2');
    const active = await page.evaluate(() => document.activeElement?.id ?? null);
    assert(active === 'sheet-grid', `expected grid to stay focused, got ${active}`);
    const preserved = await page.locator('#cell-C1').evaluate((node, expected) => node === expected, anchor);
    assert(preserved, 'selection movement replaced an unrelated cell node');
  });

  await runTest('post-render inline focus selects existing draft text', async () => {
    await page.locator('#cell-B1').click();
    await page.waitForFunction(() => document.querySelector('#sheet-grid')?.getAttribute('aria-activedescendant') === 'cell-B1');
    await page.locator('#cell-B1').dblclick();
    await page.waitForSelector('#inline-editor-B1');
    const active = await activeInputState(page);
    assert(active.id === 'inline-editor-B1', `expected inline editor focus, got ${JSON.stringify(active)}`);
    assert(active.value === '=A1 + 1', `expected B1 draft value, got ${active.value}`);
    assert(active.selectionStart === 0, `expected selection to start at 0, got ${active.selectionStart}`);
    assert(
      active.selectionEnd === active.value.length,
      `expected full selection through ${active.value.length}, got ${active.selectionEnd}`,
    );
  });

  await runTest('inline editor arrow keys keep native cursor movement', async () => {
    const input = page.locator('#inline-editor-B1');
    await input.fill('12345');
    await input.evaluate(element => element.setSelectionRange(4, 4));
    await page.keyboard.press('ArrowLeft');
    const active = await activeInputState(page);
    assert(active.id === 'inline-editor-B1', `expected inline editor to stay focused, got ${JSON.stringify(active)}`);
    assert(
      active.selectionStart === 3 && active.selectionEnd === 3,
      `expected ArrowLeft to move native cursor to 3, got ${JSON.stringify(active)}`,
    );
  });

  await runTest('Escape cancels inline draft through key resolver actions', async () => {
    await page.locator('#inline-editor-B1').fill('=A1 * 2');
    await page.keyboard.press('Escape');
    await page.waitForSelector('#inline-editor-B1', { state: 'detached' });
    await waitForCellText(page, 'B1', '11');
    assert(
      await page.locator('#formula-editor-input').inputValue() === '=A1 + 1',
      'Escape should restore B1 committed text',
    );
  });

  await runTest('Enter applies inline draft through key resolver actions', async () => {
    await page.locator('#cell-C1').dblclick();
    await page.waitForSelector('#inline-editor-C1');
    await page.locator('#inline-editor-C1').fill('7');
    await page.keyboard.press('Enter');
    await page.waitForSelector('#inline-editor-C1', { state: 'detached' });
    await waitForCellText(page, 'C1', '7');
  });

  await runTest('blur applies inline draft through pure blur descriptor', async () => {
    await page.locator('#cell-D1').dblclick();
    await page.waitForSelector('#inline-editor-D1');
    await page.locator('#inline-editor-D1').fill('9');
    await page.locator('#cell-A1').click();
    await page.waitForSelector('#inline-editor-D1', { state: 'detached' });
    await waitForCellText(page, 'D1', '9');
  });

  await runTest('formula form submit applies selected draft through pure input descriptor', async () => {
    await page.locator('#cell-A1').click();
    await page.waitForFunction(() => {
      const input = document.querySelector('#formula-editor-input');
      return input instanceof HTMLInputElement && input.getAttribute('aria-label')?.includes('A1');
    });
    await page.locator('#formula-editor-input').fill('15');
    await page.locator('.primary-action').click();
    await waitForCellText(page, 'A1', '15');
    await waitForCellText(page, 'B1', '16');
    await page.waitForFunction(() => document.querySelector('.evidence-panel')?.textContent?.includes('A1'));
    const context = await page.evaluate(() => globalThis.typedSpreadsheetAIContext?.());
    assert(context?.latest_trace?.edit === 'A1 ← 15', `AI context trace mismatch: ${JSON.stringify(context)}`);
    assert(context?.latest_evidence?.cells?.some(cell => cell.id === 'B1'), 'AI context evidence omitted dependent B1');
  });

  await runTest('reset clears trace, evidence, and exported AI context', async () => {
    await page.getByRole('button', { name: 'Reset proof' }).click();
    await waitForCellText(page, 'B1', '11');
    await page.locator('#cell-A1').click();
    await page.locator('#formula-editor-input').fill('15');
    await page.locator('.primary-action').click();
    await waitForCellText(page, 'A1', '15');
    await page.waitForFunction(() => document.querySelector('.evidence-panel')?.textContent?.includes('A1'));
    await page.getByRole('button', { name: 'Reset proof' }).click();
    await waitForCellText(page, 'B1', '11');
    await page.waitForFunction(() => {
      return document.querySelector('.evidence-panel')?.textContent?.includes('No bounded before/after evidence yet.');
    });
    const context = await page.evaluate(() => globalThis.typedSpreadsheetAIContext?.());
    assert(context?.selected_cell === 'B1', `reset selected cell mismatch: ${JSON.stringify(context)}`);
    assert(context?.latest_trace == null, `reset retained latest trace: ${JSON.stringify(context)}`);
    assert(context?.latest_evidence == null, `reset retained latest evidence: ${JSON.stringify(context)}`);
  });

  assert(pageErrors.length === 0, `Page errors: ${pageErrors.map(error => error.message).join('\n')}`);
} finally {
  if (browser) await browser.close();
  await new Promise(resolve => server.close(resolve));
}
