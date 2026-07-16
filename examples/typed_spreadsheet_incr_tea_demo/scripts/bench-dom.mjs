import { chromium } from 'playwright';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const distRoot = resolve(fileURLToPath(new URL('../dist/', import.meta.url)));
const host = '127.0.0.1';
const samples = Number(process.env.BENCH_SAMPLES ?? 10);
const warmups = Number(process.env.BENCH_WARMUPS ?? 2);

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function contentType(filePath) {
  switch (extname(filePath)) {
    case '.html': return 'text/html; charset=utf-8';
    case '.js': return 'text/javascript; charset=utf-8';
    case '.css': return 'text/css; charset=utf-8';
    default: return 'application/octet-stream';
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
    return document.getElementById(id)?.textContent?.trim() === text;
  }, { id: `cell-${cell}`, text: expected });
}

async function resetPage(page) {
  await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('#cell-AX50');
  await waitForCellText(page, 'B1', '11');
  await page.waitForFunction(() => {
    return document.querySelector('#sheet-grid')?.getAttribute('aria-activedescendant') === 'cell-B1';
  });
  await page.waitForFunction(() => {
    return document.querySelector('.evidence-panel')?.textContent?.includes('No bounded before/after evidence yet.');
  });
}

async function measure(page, scenario) {
  return page.evaluate(async ({ scenario }) => {
    const nextFrame = () => new Promise(resolve => setTimeout(resolve, 0));
    const waitFor = async (selectorOrPredicate) => {
      for (let i = 0; i < 60; i += 1) {
        const result = typeof selectorOrPredicate === 'function'
          ? selectorOrPredicate()
          : document.querySelector(selectorOrPredicate);
        if (result) return result;
        await nextFrame();
      }
      throw new Error(`Timed out waiting for ${selectorOrPredicate}`);
    };
    const waitForCellText = async (id, text) => {
      await waitFor(() => document.getElementById(id)?.textContent?.trim() === text);
    };
    const bench = globalThis.__typedSpreadsheetBench;
    if (!bench || typeof bench.dispatch !== 'function') {
      throw new Error('typed spreadsheet benchmark API is missing');
    }
    const start = performance.now();
    if (scenario === 'selection') {
      bench.dispatch('select-c1');
      await waitFor('[aria-activedescendant="cell-C1"]');
    } else if (scenario === 'visible-edit') {
      bench.dispatch('edit-a1');
      await waitForCellText('cell-A1', '15');
    } else if (scenario === 'formula-dependency') {
      bench.dispatch('edit-a1');
      await waitForCellText('cell-B1', '16');
    } else if (scenario === 'formula-bar-draft') {
      bench.dispatch('draft-a1');
      await waitFor(() => {
        const context = globalThis.typedSpreadsheetAIContext?.();
        return context?.selected_cell === 'A1' &&
          context.cells?.some(cell => cell.id === 'A1' && cell.draft_text === '15');
      });
    } else if (scenario === 'trace-evidence-update') {
      bench.dispatch('edit-b1');
      await waitForCellText('cell-B1', '20');
      await waitFor(() => document.querySelector('.evidence-panel')?.textContent?.includes('B1'));
    } else if (scenario === 'offscreen-edit') {
      bench.dispatch('edit-ax50');
      await waitForCellText('cell-AX50', '17');
    } else {
      throw new Error(`Unknown benchmark scenario: ${scenario}`);
    }
    return performance.now() - start;
  }, { scenario });
}

function percentile(values, fraction) {
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(sorted.length - 1, Math.ceil(sorted.length * fraction) - 1);
  return sorted[index];
}

const budgets = {
  selection: 16,
  'formula-bar-draft': 16,
  'visible-edit': 50,
  'formula-dependency': 100,
  'trace-evidence-update': 100,
  'offscreen-edit': 100,
};

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
  assert(address && typeof address === 'object', 'Benchmark server did not bind to a TCP port');
  const baseUrl = `http://${host}:${address.port}`;
  browser = await chromium.launch({ headless: process.env.HEADLESS !== '0' });
  const page = await browser.newPage();
  await page.addInitScript(() => {
    window.requestAnimationFrame = () => 0;
    window.cancelAnimationFrame = () => {};
  });
  await page.goto(`${baseUrl}/?bench`, { waitUntil: 'load' });
  await page.waitForSelector('#cell-AX50');
  await waitForCellText(page, 'B1', '11');

  const results = [];
  for (const scenario of Object.keys(budgets)) {
    for (let i = 0; i < warmups; i += 1) {
      await resetPage(page);
      await measure(page, scenario);
    }
    const durations = [];
    for (let i = 0; i < samples; i += 1) {
      await resetPage(page);
      durations.push(await measure(page, scenario));
    }
    const result = {
      scenario,
      samples,
      min_ms: Math.min(...durations),
      p50_ms: percentile(durations, 0.5),
      p95_ms: percentile(durations, 0.95),
      max_ms: Math.max(...durations),
      budget_ms: budgets[scenario],
    };
    result.within_budget = result.p95_ms <= result.budget_ms;
    results.push(result);
  }

  console.log(JSON.stringify({
    target: 'Chromium DOM, 50x50 typed spreadsheet dispatch-to-synchronous-render',
    samples,
    warmups,
    results,
  }, null, 2));
  if (process.env.ENFORCE_BUDGET === '1' && results.some(result => !result.within_budget)) {
    process.exitCode = 2;
  }
} finally {
  if (browser) await browser.close();
  await new Promise(resolve => server.close(resolve));
}
