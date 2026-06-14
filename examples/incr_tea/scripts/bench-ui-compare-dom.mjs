import { chromium } from 'playwright';
import { assert, close, createStaticServer, host, listen } from './browser-harness.mjs';

const systems = ['incr_tea', 'rabbita', 'luna'];
const suites = [
  {
    name: 'counter',
    title: 'Counter',
    operations: ['initial-mount', 'displayed-count', 'unrelated'],
    sizes: [0],
  },
  {
    name: 'keyed-list',
    title: 'Keyed list',
    operations: ['prepend', 'remove-first', 'reverse'],
    sizes: [16, 64, 256],
  },
  {
    name: 'panel',
    title: 'Hidden/visible panel',
    operations: ['hidden-update', 'open', 'visible-update', 'close'],
    sizes: [0],
  },
  {
    name: 'row-leaf',
    title: 'Row/leaf locality',
    operations: ['row-text', 'row-class', 'hot-leaf-text'],
    sizes: [16, 64, 256],
  },
];
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
  if (!result) return '—';
  return `${fmt(result.mean_us)} ± ${fmt(result.stdev_us)}`;
}

function keyOf({ system, suite, operation, n = 0 }) {
  return `${system}:${suite}:${operation}:${n}`;
}

function summarize(raw) {
  const results = new Map();
  for (const result of raw) {
    const mean_us = mean(result.samples);
    const stdev_us = stdev(result.samples);
    results.set(keyOf(result), {
      ...result,
      mean_us,
      stdev_us,
    });
  }
  return results;
}

function systemCells(results, suite, operation, n = 0) {
  return systems.map(system => cell(results.get(keyOf({ system, suite, operation, n }))));
}

function counterTable(results) {
  const suite = suites.find(item => item.name === 'counter');
  const lines = [
    `### ${suite.title} (µs/op)`,
    '',
    '| operation | incr_tea | Rabbita | Luna |',
    '|---|---:|---:|---:|',
  ];
  for (const operation of suite.operations) {
    lines.push(`| ${operation} | ${systemCells(results, suite.name, operation).join(' | ')} |`);
  }
  return lines.join('\n');
}

function keyedListTable(results) {
  const suite = suites.find(item => item.name === 'keyed-list');
  const lines = [
    `### ${suite.title} (µs/op)`,
    '',
    '| operation | N | incr_tea | Rabbita | Luna |',
    '|---|---:|---:|---:|---:|',
  ];
  for (const operation of suite.operations) {
    const label = operation === 'reverse' ? 'reverse†' : operation;
    for (const n of suite.sizes) {
      lines.push(`| ${label} | ${n} | ${systemCells(results, suite.name, operation, n).join(' | ')} |`);
    }
  }
  return lines.join('\n');
}

function panelTable(results) {
  const suite = suites.find(item => item.name === 'panel');
  const lines = [
    `### ${suite.title} (µs/op)`,
    '',
    '| operation | incr_tea | Rabbita | Luna |',
    '|---|---:|---:|---:|',
  ];
  for (const operation of suite.operations) {
    lines.push(`| ${operation} | ${systemCells(results, suite.name, operation).join(' | ')} |`);
  }
  return lines.join('\n');
}

function rowLeafTable(results) {
  const suite = suites.find(item => item.name === 'row-leaf');
  const labels = new Map([
    ['row-text', 'same-order row text'],
    ['row-class', 'same-order row class'],
    ['hot-leaf-text', 'hot nested text leaf'],
  ]);
  const lines = [
    `### ${suite.title} (µs/op)`,
    '',
    '| operation | N | incr_tea | Rabbita | Luna |',
    '|---|---:|---:|---:|---:|',
  ];
  for (const operation of suite.operations) {
    for (const n of suite.sizes) {
      lines.push(`| ${labels.get(operation) ?? operation} | ${n} | ${systemCells(results, suite.name, operation, n).join(' | ')} |`);
    }
  }
  return lines.join('\n');
}

function resultsTables(results) {
  return [counterTable(results), keyedListTable(results), panelTable(results), rowLeafTable(results)].join('\n\n');
}

function plannedCells() {
  const cells = [];
  for (const suite of suites) {
    for (const system of systems) {
      for (const operation of suite.operations) {
        for (const n of suite.sizes) {
          cells.push({ system, suite: suite.name, operation, n });
        }
      }
    }
  }
  return cells;
}

function printReport({ browserVersion, userAgent, raw }) {
  const results = summarize(raw);
  const report = [
    '# Incremental TEA adjacent-framework mounted matrix benchmark',
    '',
    `- Browser: Chromium ${browserVersion}`,
    `- User agent: ${userAgent}`,
    `- Samples: ${samples} × ${iterations} operations per cell`,
    '- Unit: mean ± sample standard deviation, microseconds per timed operation',
    '- Hosts are attached to the document but hidden offscreen.',
    '- The page uses an immediate requestAnimationFrame shim so Rabbita measurements include the scheduled flush work without browser frame-wait latency.',
    '- Keyed-list reset work runs between timed operations and is not included in the timing window.',
    '- Row/leaf locality rows keep keys and order fixed; each operation toggles one hot middle row or nested leaf and includes no reset work in the timed window.',
    '- Rabbita keyed children use its Map-based keyed-child API; Luna list rows use luna/dom for_each reference/value reconciliation over stable string ids. Treat identity/focus behavior as framework-specific rather than semantically identical.',
    '- † Rabbita has no ordered key-array API in this harness; read its reverse cells as keyed Map dirty/update costs, not ordered reversal equivalence.',
    '',
    '## Results',
    '',
    resultsTables(results),
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
  await page.waitForFunction(() => globalThis.__incrTeaUiCompareDomBench?.runCell);
  const userAgent = await page.evaluate(() => navigator.userAgent);

  const raw = [];
  for (const benchCell of plannedCells()) {
    const result = await page.evaluate(
      args => globalThis.__incrTeaUiCompareDomBench.runCell(
        args.system,
        args.suite,
        args.operation,
        args.n,
        args.iterations,
        args.samples,
      ),
      { ...benchCell, iterations, samples },
    );
    raw.push(result);
  }

  printReport({ browserVersion: browser.version(), userAgent, raw });
} finally {
  if (browser) await browser.close();
  await close(server);
}
