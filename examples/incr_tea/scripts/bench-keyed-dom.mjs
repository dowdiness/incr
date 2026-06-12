import { chromium } from 'playwright';
import { assert, close, createStaticServer, host, listen } from './browser-harness.mjs';

const sizes = [16, 64, 256];
const operations = ['prepend', 'remove-first', 'reverse'];
const modes = ['keyed', 'rebuild'];
const iterations = positiveInt(process.env.INCR_TEA_DOM_BENCH_ITERATIONS, 200);
const samples = positiveInt(process.env.INCR_TEA_DOM_BENCH_SAMPLES, 9);

function positiveInt(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? Math.trunc(parsed) : fallback;
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

const server = createStaticServer('/examples/incr_tea/bench.html');

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
