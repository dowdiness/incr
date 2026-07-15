import { chromium } from 'playwright';
import { assert, close, createStaticServer, host, listen } from './browser-harness.mjs';

const nodeCounts = [0, 100, 1000, 10000];
const controlledCounts = [0, 1, 16, 256];
const modes = ['equal-no-drift', 'mismatch-repair'];
const iterations = positiveInt(process.env.INCR_TEA_CONTROLLED_BENCH_ITERATIONS, 200);
const samples = positiveInt(process.env.INCR_TEA_CONTROLLED_BENCH_SAMPLES, 9);

function positiveInt(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? Math.trunc(parsed) : fallback;
}

function fmt(value) {
  if (value >= 100) return value.toFixed(0);
  if (value >= 10) return value.toFixed(1);
  return value.toFixed(2);
}

function percentile(values, fraction) {
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(sorted.length - 1, Math.ceil(sorted.length * fraction) - 1);
  return sorted[index];
}

function stats(samplesUs) {
  return {
    median_us: percentile(samplesUs, 0.5),
    p95_us: percentile(samplesUs, 0.95),
    min_us: Math.min(...samplesUs),
    max_us: Math.max(...samplesUs),
  };
}

function keyOf(result) {
  return `${result.mode}:${result.nodes}:${result.controlled}`;
}

function reportTable(results, mode) {
  const rows = results.filter(result => result.mode === mode);
  const lines = [
    `### ${mode} (µs per equal-view flush)`,
    '',
    '| nodes | controlled | median | p95 | min | max |',
    '|---:|---:|---:|---:|---:|---:|',
  ];
  for (const result of rows) {
    const summary = stats(result.samples);
    lines.push(
      `| ${result.nodes} | ${result.controlled} | ${fmt(summary.median_us)} | ${fmt(summary.p95_us)} | ${fmt(summary.min_us)} | ${fmt(summary.max_us)} |`,
    );
  }
  return lines.join('\n');
}

function printReport({ browserVersion, userAgent, raw }) {
  const results = raw.map(result => ({ ...result, ...stats(result.samples) }));
  console.log('# Incremental TEA controlled-property reconciliation benchmark');
  console.log('');
  console.log(`- Browser: ${browserVersion}`);
  console.log(`- User agent: ${userAgent}`);
  console.log(`- Samples: ${samples} × ${iterations} operations per cell`);
  console.log('- Unit: microseconds per timed `BrowserRenderer::flush_all` equal-view flush');
  console.log('- Timed window excludes tree construction, browser-property drift, and model dispatch.');
  console.log('- Median and p95 are computed across per-sample means; min/max expose run spread.');
  console.log('');
  for (const mode of modes) console.log(reportTable(results, mode), '\n');
  console.log('<details>');
  console.log('<summary>Raw JSON</summary>');
  console.log('');
  console.log('```json');
  console.log(JSON.stringify(results, null, 2));
  console.log('```');
  console.log('</details>');
}

const server = createStaticServer('/examples/incr_tea/controlled-reconcile-bench.html');
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
  await page.goto(`${baseUrl}/examples/incr_tea/controlled-reconcile-bench.html`, { waitUntil: 'load' });
  await page.waitForFunction(
    () => globalThis.__incrTeaControlledReconcileBench?.run,
    undefined,
    { polling: 50 },
  );
  const userAgent = await page.evaluate(() => navigator.userAgent);

  const raw = [];
  for (const mode of modes) {
    for (const nodes of nodeCounts) {
      for (const controlled of controlledCounts) {
        if (controlled > nodes) continue;
        raw.push(await page.evaluate(
          args => globalThis.__incrTeaControlledReconcileBench.run(
            args.mode,
            args.nodes,
            args.controlled,
            args.iterations,
            args.samples,
          ),
          { mode, nodes, controlled, iterations, samples },
        ));
      }
    }
  }

  printReport({ browserVersion: browser.version(), userAgent, raw });
} finally {
  if (browser) await browser.close();
  await close(server);
}
