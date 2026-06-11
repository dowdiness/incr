import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const scriptDir = fileURLToPath(new URL('.', import.meta.url));
const repoRoot = resolve(scriptDir, '../../..');
const host = '127.0.0.1';
const sizes = [16, 64, 256];
const operations = ['prepend', 'remove-first', 'reverse'];
const modes = ['keyed', 'rebuild'];
const iterations = positiveInt(process.env.INCR_TEA_DOM_BENCH_ITERATIONS, 200);
const samples = positiveInt(process.env.INCR_TEA_DOM_BENCH_SAMPLES, 9);

function positiveInt(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? Math.trunc(parsed) : fallback;
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function contentType(filePath) {
  switch (extname(filePath)) {
    case '.html':
      return 'text/html; charset=utf-8';
    case '.js':
      return 'text/javascript; charset=utf-8';
    case '.css':
      return 'text/css; charset=utf-8';
    case '.json':
      return 'application/json; charset=utf-8';
    default:
      return 'application/octet-stream';
  }
}

function filePathForRequest(pathname) {
  const localPath = pathname === '/' ? '/examples/incr_tea/bench.html' : decodeURIComponent(pathname);
  const filePath = resolve(repoRoot, `.${localPath}`);
  assert(
    filePath === repoRoot || filePath.startsWith(`${repoRoot}${sep}`),
    `Refusing to serve path outside repo: ${pathname}`,
  );
  return filePath;
}

function listen(server) {
  return new Promise((resolveListen, reject) => {
    server.once('error', reject);
    server.listen(0, host, resolveListen);
  });
}

function close(server) {
  return new Promise(resolveClose => server.close(resolveClose));
}

function mean(values) {
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function stdev(values) {
  if (values.length < 2) return 0;
  const avg = mean(values);
  const variance = values.reduce((sum, value) => sum + (value - avg) ** 2, 0) / (values.length - 1);
  return Math.sqrt(variance);
}

function fmt(value) {
  if (value < 10) return value.toFixed(2);
  if (value < 100) return value.toFixed(1);
  return value.toFixed(0);
}

function cell(result) {
  return `${fmt(result.mean_us)} ± ${fmt(result.stdev_us)}`;
}

function markdownTable(results, mode) {
  const lines = [
    `### ${mode === 'keyed' ? 'Keyed applier' : 'Non-keyed rebuild baseline'} (µs/op)`,
    '',
    '| operation | N=16 | N=64 | N=256 |',
    '|---|---:|---:|---:|',
  ];
  for (const operation of operations) {
    lines.push(`| ${operation} | ${sizes.map(n => cell(results.get(`${mode}:${operation}:${n}`))).join(' | ')} |`);
  }
  return lines.join('\n');
}

function ratioTable(results) {
  const lines = [
    '### Rebuild / keyed ratio',
    '',
    '| operation | N=16 | N=64 | N=256 |',
    '|---|---:|---:|---:|',
  ];
  for (const operation of operations) {
    const ratios = sizes.map(n => {
      const keyed = results.get(`keyed:${operation}:${n}`).mean_us;
      const rebuild = results.get(`rebuild:${operation}:${n}`).mean_us;
      return `${fmt(rebuild / keyed)}×`;
    });
    lines.push(`| ${operation} | ${ratios.join(' | ')} |`);
  }
  return lines.join('\n');
}

function summarize(raw) {
  const results = new Map();
  for (const result of raw) {
    const mean_us = mean(result.samples);
    const stdev_us = stdev(result.samples);
    results.set(`${result.mode}:${result.operation}:${result.n}`, {
      ...result,
      mean_us,
      stdev_us,
    });
  }
  return results;
}

function printReport({ browserVersion, userAgent, raw }) {
  const results = summarize(raw);
  const report = [
    '# Incremental TEA keyed DOM applier benchmark',
    '',
    `- Browser: Chromium ${browserVersion}`,
    `- User agent: ${userAgent}`,
    `- Samples: ${samples} × ${iterations} operations per cell`,
    '- Unit: mean ± sample standard deviation, microseconds per timed operation',
    '- Reset back to the N-item baseline runs between timed operations and is not included in the timing window.',
    '',
    markdownTable(results, 'keyed'),
    '',
    markdownTable(results, 'rebuild'),
    '',
    ratioTable(results),
    '',
    '<details><summary>Raw JSON</summary>',
    '',
    '```json',
    JSON.stringify(raw, null, 2),
    '```',
    '',
    '</details>',
  ].join('\n');
  console.log(report);
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

await listen(server);

let browser;
try {
  const address = server.address();
  assert(address && typeof address === 'object', 'Benchmark server did not bind to a TCP port');
  const baseUrl = `http://${host}:${address.port}`;

  browser = await chromium.launch({ headless: process.env.HEADLESS !== '0' });
  const page = await browser.newPage();
  page.on('pageerror', error => {
    throw error;
  });
  await page.goto(`${baseUrl}/examples/incr_tea/bench.html`, { waitUntil: 'load' });
  await page.waitForFunction(() => globalThis.__incrTeaDomBench?.run);
  const userAgent = await page.evaluate(() => navigator.userAgent);

  const raw = [];
  for (const mode of modes) {
    for (const operation of operations) {
      for (const n of sizes) {
        const result = await page.evaluate(
          args => globalThis.__incrTeaDomBench.run(
            args.mode,
            args.operation,
            args.n,
            args.iterations,
            args.samples,
          ),
          { mode, operation, n, iterations, samples },
        );
        raw.push(result);
      }
    }
  }

  printReport({ browserVersion: browser.version(), userAgent, raw });
} finally {
  if (browser) await browser.close();
  await close(server);
}
