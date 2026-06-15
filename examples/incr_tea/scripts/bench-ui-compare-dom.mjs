import { chromium } from 'playwright';
import { assert, close, createStaticServer, host, listen } from './browser-harness.mjs';

const defaultSystems = ['incr_tea', 'rabbita', 'luna'];
const inactiveCohortBursts = [10, 100, 1000];
const inactiveCohortActivationModes = ['activate-one', 'activate-all'];
const inactiveCohortTimings = ['total', 'activation'];
const inactiveCohortOperations = inactiveCohortBursts.flatMap(burst =>
  inactiveCohortActivationModes.flatMap(mode =>
    inactiveCohortTimings.map(timing => `inactive-${burst}-updates-${mode}-${timing}`),
  ),
);
const suites = [
  {
    name: 'counter',
    title: 'Counter',
    systems: defaultSystems,
    operations: ['initial-mount', 'displayed-count', 'unrelated'],
    sizes: [0],
  },
  {
    name: 'keyed-list',
    title: 'Keyed list',
    systems: defaultSystems,
    operations: ['prepend', 'remove-first', 'reverse'],
    sizes: [16, 64, 256],
  },
  {
    name: 'panel',
    title: 'Hidden/visible panel',
    systems: defaultSystems,
    operations: ['hidden-update', 'open', 'visible-update', 'close'],
    sizes: [0],
  },
  {
    name: 'row-leaf',
    title: 'Row/leaf locality',
    systems: ['incr_tea', 'incr_tea-direct', 'rabbita', 'luna'],
    operations: ['row-text', 'row-class', 'hot-leaf-text'],
    sizes: [16, 64, 256],
  },
  {
    name: 'workspace-island',
    title: 'Collapsed/hidden workspace island',
    systems: defaultSystems,
    operations: ['collapsed-update', 'hidden-mounted-update', 'visible-update'],
    sizes: [64, 256, 512],
  },
  {
    name: 'workspace-inactive-root',
    title: 'DOM-preserving inactive workspace root',
    systems: ['incr_tea'],
    operations: ['active-hidden-mounted-update', 'inactive-update', 'activation-catch-up'],
    sizes: [64, 256, 512],
  },
  {
    name: 'workspace-inactive-root-amortized',
    title: 'Amortized inactive workspace root',
    systems: ['incr_tea'],
    operations: [
      'inactive-10-updates-activation',
      'inactive-100-updates-activation',
      'inactive-1000-updates-activation',
    ],
    sizes: [64, 256, 512],
  },
  {
    name: 'workspace-inactive-root-cohort',
    title: 'Inactive workspace root cohort',
    systems: ['incr_tea'],
    operations: inactiveCohortOperations,
    sizes: [1, 4, 16],
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

function systemsFor(suiteName) {
  return suites.find(item => item.name === suiteName)?.systems ?? defaultSystems;
}

function systemCells(results, suite, operation, n = 0) {
  return systemsFor(suite).map(system => cell(results.get(keyOf({ system, suite, operation, n }))));
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
    '| operation | N | incr_tea | incr_tea-direct | Rabbita | Luna |',
    '|---|---:|---:|---:|---:|---:|',
  ];
  for (const operation of suite.operations) {
    for (const n of suite.sizes) {
      lines.push(`| ${labels.get(operation) ?? operation} | ${n} | ${systemCells(results, suite.name, operation, n).join(' | ')} |`);
    }
  }
  return lines.join('\n');
}

function workspaceIslandTable(results) {
  const suite = suites.find(item => item.name === 'workspace-island');
  const labels = new Map([
    ['collapsed-update', 'collapsed update'],
    ['hidden-mounted-update', 'hidden mounted update'],
    ['visible-update', 'visible update'],
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

function inactiveWorkspaceTable(results) {
  const suite = suites.find(item => item.name === 'workspace-inactive-root');
  const labels = new Map([
    ['active-hidden-mounted-update', 'active hidden-mounted update'],
    ['inactive-update', 'inactive update'],
    ['activation-catch-up', 'activation catch-up'],
  ]);
  const lines = [
    `### ${suite.title} (µs/op)`,
    '',
    '| operation | N | incr_tea |',
    '|---|---:|---:|',
  ];
  for (const operation of suite.operations) {
    for (const n of suite.sizes) {
      lines.push(`| ${labels.get(operation) ?? operation} | ${n} | ${systemCells(results, suite.name, operation, n).join(' | ')} |`);
    }
  }
  return lines.join('\n');
}

function inactiveWorkspaceAmortizedTable(results) {
  const suite = suites.find(item => item.name === 'workspace-inactive-root-amortized');
  const labels = new Map([
    ['inactive-10-updates-activation', '10 inactive updates + activation'],
    ['inactive-100-updates-activation', '100 inactive updates + activation'],
    ['inactive-1000-updates-activation', '1000 inactive updates + activation'],
  ]);
  const lines = [
    `### ${suite.title} (µs/burst)`,
    '',
    '| burst | N | incr_tea total |',
    '|---|---:|---:|',
  ];
  for (const operation of suite.operations) {
    for (const n of suite.sizes) {
      lines.push(`| ${labels.get(operation) ?? operation} | ${n} | ${systemCells(results, suite.name, operation, n).join(' | ')} |`);
    }
  }
  return lines.join('\n');
}

function inactiveCohortParts(operation) {
  const match = /^inactive-(\d+)-updates-activate-(one|all)-(total|activation)$/.exec(operation);
  if (!match) return { burst: operation, activation: '—', timing: '—' };
  return {
    burst: `${match[1]} inactive updates`,
    activation: match[2] === 'one' ? 'one root' : 'all roots',
    timing: match[3] === 'activation' ? 'activation only' : 'total burst',
  };
}

function inactiveWorkspaceCohortTable(results) {
  const suite = suites.find(item => item.name === 'workspace-inactive-root-cohort');
  const lines = [
    `### ${suite.title} (µs)`,
    '',
    '| burst | activation | timing | roots | incr_tea |',
    '|---|---|---|---:|---:|',
  ];
  for (const operation of suite.operations) {
    const parts = inactiveCohortParts(operation);
    for (const n of suite.sizes) {
      lines.push(`| ${parts.burst} | ${parts.activation} | ${parts.timing} | ${n} | ${systemCells(results, suite.name, operation, n).join(' | ')} |`);
    }
  }
  return lines.join('\n');
}

function resultsTables(results) {
  return [counterTable(results), keyedListTable(results), panelTable(results), rowLeafTable(results), workspaceIslandTable(results), inactiveWorkspaceTable(results), inactiveWorkspaceAmortizedTable(results), inactiveWorkspaceCohortTable(results)].join('\n\n');
}

function plannedCells() {
  const cells = [];
  for (const suite of suites) {
    for (const system of suite.systems) {
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
    '- Workspace-island rows keep one editor/sidebar/inspector-shaped subtree at a fixed size. Collapsed updates keep that subtree absent/untracked; hidden-mounted updates keep the subtree in the DOM with hidden/aria-hidden attributes and current active watchers; visible updates keep it visible. Mode reset work runs before the timed operation.',
    '- Workspace-inactive-root rows use the same subtree with the `BrowserRenderer` inactive-root prototype. Active hidden-mounted update is the same root active; inactive update keeps DOM attached but skips the watched-view read; activation catch-up measures the deferred flush after one inactive update. Reset work runs before the timed operation.',
    '- Workspace-inactive-root-amortized rows time one burst: K inactive updates, each using the inactive flush-skip path, followed by one activation catch-up. Reset/deactivate work runs before the timed burst.',
    '- Workspace-inactive-root-cohort rows mount one shared workspace Program into R inactive DOM roots (R is the roots column; per-root subtree N=256). Each burst applies K model updates while all roots are inactive; every update walks the inactive flush-skip path for all roots. Total rows time updates plus activation; activation-only rows run the same burst before timing and measure only activating one root or all roots.',
    '- incr_tea-direct is an experimental row/leaf-only direct patch path: Html stores pure leaf/attr ids, while mount-boundary watches resolve live text/class values.',
    '- Rabbita keyed-list cells use its Map-based keyed-child API for every keyed-list operation; Luna list rows use luna/dom for_each reference/value reconciliation over stable string ids. Treat identity/focus behavior as framework-specific rather than semantically identical.',
    '- † Rabbita has no ordered key-array API in this harness; read its keyed-list cells, especially reverse, as keyed Map dirty/update costs rather than ordered-list equivalence.',
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
  await page.waitForFunction(
    () => globalThis.__incrTeaUiCompareDomBench?.runCell,
    undefined,
    { polling: 50 },
  );
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
