import { chromium } from 'playwright';
import { assert, close, createStaticServer, host, listen } from './browser-harness.mjs';

const systems = ['incr_tea', 'rabbita', 'luna'];
const operations = ['initial-mount', 'displayed-count', 'unrelated'];
const iterations = positiveInt(process.env.INCR_TEA_UI_COMPARE_DOM_BENCH_ITERATIONS, 200);
const samples = positiveInt(process.env.INCR_TEA_UI_COMPARE_DOM_BENCH_SAMPLES, 9);

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

function summarize(raw) {
  const results = new Map();
  for (const result of raw) {
    const mean_us = mean(result.samples);
    const stdev_us = stdev(result.samples);
    results.set(`${result.system}:${result.operation}`, {
      ...result,
      mean_us,
      stdev_us,
    });
  }
  return results;
}

function resultsTable(results) {
  const lines = [
    '## Results (µs/op)',
    '',
    '| operation | incr_tea | Rabbita | Luna |',
    '|---|---:|---:|---:|',
  ];
  for (const operation of operations) {
    lines.push(`| ${operation} | ${systems.map(system => cell(results.get(`${system}:${operation}`))).join(' | ')} |`);
  }
  return lines.join('\n');
}

function printReport({ browserVersion, userAgent, raw }) {
  const results = summarize(raw);
  const report = [
    '# Incremental TEA adjacent-framework mounted counter benchmark',
    '',
    `- Browser: Chromium ${browserVersion}`,
    `- User agent: ${userAgent}`,
    `- Samples: ${samples} × ${iterations} operations per cell`,
    '- Unit: mean ± sample standard deviation, microseconds per timed operation',
    '- Hosts are attached to the document but hidden offscreen.',
    '- The page uses an immediate requestAnimationFrame shim so Rabbita measurements include the scheduled flush work without browser frame-wait latency.',
    '',
    resultsTable(results),
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

const server = createStaticServer('/examples/incr_tea/ui-compare-bench.html');

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
  await page.goto(`${baseUrl}/examples/incr_tea/ui-compare-bench.html`, { waitUntil: 'load' });
  await page.waitForFunction(() => globalThis.__incrTeaUiCompareDomBench?.run);
  const userAgent = await page.evaluate(() => navigator.userAgent);

  const raw = [];
  for (const system of systems) {
    for (const operation of operations) {
      const result = await page.evaluate(
        args => globalThis.__incrTeaUiCompareDomBench.run(
          args.system,
          args.operation,
          args.iterations,
          args.samples,
        ),
        { system, operation, iterations, samples },
      );
      raw.push(result);
    }
  }

  printReport({ browserVersion: browser.version(), userAgent, raw });
} finally {
  if (browser) await browser.close();
  await close(server);
}
