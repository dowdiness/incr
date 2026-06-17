import { chromium } from 'playwright';
import { assert, close, createStaticServer, host, listen } from './browser-harness.mjs';

const rootCounts = [1, 4, 16];
const ownerships = ['shared', 'independent'];
const triggerOperations = [
  'observer-dispatch-only',
  'observer-activate-one',
  'observer-activate-all',
  'manual-activate-one',
  'manual-activate-all',
];
const policyOperations = [
  'semantic-show-one',
  'prewarm-hit-one',
  'prewarm-miss-one',
  'semantic-show-all',
  'prewarm-hit-all',
  'prewarm-miss-all',
];
const operations = [...triggerOperations, ...policyOperations];
const samples = positiveInt(process.env.INCR_TEA_ACTIVATION_TRIGGER_SAMPLES, 9);
const inactiveUpdates = positiveInt(process.env.INCR_TEA_ACTIVATION_TRIGGER_UPDATES, 1);
const timeoutMs = positiveInt(process.env.INCR_TEA_ACTIVATION_TRIGGER_TIMEOUT_MS, 1000);

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
  return raw.map(result => ({
    ...result,
    mean_us: mean(result.samples),
    stdev_us: stdev(result.samples),
  }));
}

function keyOf(result) {
  return `${result.ownership}:${result.n}:${result.operation}`;
}

async function measureCell(page, { ownership, rootCount, operation }) {
  return page.evaluate(
    async ({ ownership, rootCount, operation, samples, inactiveUpdates, timeoutMs }) => {
      const api = globalThis.__incrTeaActivationTriggerBench;
      if (!api) throw new Error('activation-trigger bench API is not installed');

      const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
      const resetHosts = () => {
        for (let i = 0; i < api.hostCount(); i += 1) {
          const host = api.host(i);
          host.style.left = '-10000px';
          host.style.top = '0px';
          host.style.visibility = 'hidden';
        }
      };
      const prepareInactive = async () => {
        api.reset();
        resetHosts();
        api.deactivateAll();
        api.inactiveUpdates(inactiveUpdates);
        await delay(0);
      };
      const withTimeout = (promise, cleanup) => new Promise((resolve, reject) => {
        let settled = false;
        const timer = setTimeout(() => {
          if (settled) return;
          settled = true;
          cleanup();
          reject(new Error(`timed out waiting for ${operation}`));
        }, timeoutMs);
        promise.then(
          value => {
            if (settled) return;
            settled = true;
            clearTimeout(timer);
            resolve(value);
          },
          error => {
            if (settled) return;
            settled = true;
            clearTimeout(timer);
            reject(error);
          },
        );
      });
      const observeOne = async callback => {
        const host = api.host(0);
        let handle = null;
        const cleanup = () => {
          if (handle !== null) api.disconnect(handle);
          handle = null;
        };
        const done = new Promise(resolve => {
          handle = api.observe(0, () => {
            try {
              callback();
            } finally {
              cleanup();
              resolve(performance.now());
            }
          });
        });
        await delay(0);
        const started = performance.now();
        host.style.visibility = 'visible';
        host.style.left = '0px';
        const ended = await withTimeout(done, cleanup);
        return ended - started;
      };
      const observeAll = async callback => {
        const count = api.hostCount();
        let remaining = count;
        let callbackCalled = false;
        const handles = [];
        const cleanup = () => {
          for (const handle of handles) api.disconnect(handle);
          handles.length = 0;
        };
        const done = new Promise(resolve => {
          for (let i = 0; i < count; i += 1) {
            const handle = api.observe(i, () => {
              if (!callbackCalled) {
                callbackCalled = true;
                callback();
              }
              api.disconnect(handle);
              const index = handles.indexOf(handle);
              if (index >= 0) handles.splice(index, 1);
              remaining -= 1;
              if (remaining === 0) resolve(performance.now());
            });
            handles.push(handle);
          }
        });
        await delay(0);
        const started = performance.now();
        for (let i = 0; i < count; i += 1) {
          const host = api.host(i);
          host.style.visibility = 'visible';
          host.style.left = '0px';
        }
        const ended = await withTimeout(done, cleanup);
        return ended - started;
      };

      const setupInfo = api.setup(rootCount, ownership);
      const sampleValues = [];
      const activationFlushes = () => api.stats().activationFlushes;
      const expectActivationDelta = (before, expected, phase) => {
        const actual = activationFlushes() - before;
        if (actual !== expected) {
          throw new Error(
            `activation sanity check failed for ${operation} during ${phase}: expected delta ${expected}, saw ${actual}`,
          );
        }
      };
      try {
        for (let sample = 0; sample < samples; sample += 1) {
          await prepareInactive();
          let before = activationFlushes();
          if (operation === 'observer-dispatch-only') {
            sampleValues.push((await observeAll(() => {})) * 1000);
            expectActivationDelta(before, 0, 'observer dispatch');
          } else if (operation === 'observer-activate-one') {
            sampleValues.push((await observeOne(() => api.activateOne())) * 1000);
            expectActivationDelta(before, 1, 'observer activation');
          } else if (operation === 'observer-activate-all') {
            sampleValues.push((await observeAll(() => api.activateAll())) * 1000);
            expectActivationDelta(before, setupInfo.rootCount, 'observer activation');
          } else if (operation === 'manual-activate-one') {
            const started = performance.now();
            api.activateOne();
            sampleValues.push((performance.now() - started) * 1000);
            expectActivationDelta(before, 1, 'manual activation');
          } else if (operation === 'manual-activate-all') {
            const started = performance.now();
            api.activateAll();
            sampleValues.push((performance.now() - started) * 1000);
            expectActivationDelta(before, setupInfo.rootCount, 'manual activation');
          } else if (operation === 'semantic-show-one' || operation === 'prewarm-miss-one') {
            const started = performance.now();
            api.showOne();
            sampleValues.push((performance.now() - started) * 1000);
            expectActivationDelta(before, 1, 'semantic show');
          } else if (operation === 'semantic-show-all' || operation === 'prewarm-miss-all') {
            const started = performance.now();
            api.showAll();
            sampleValues.push((performance.now() - started) * 1000);
            expectActivationDelta(before, setupInfo.rootCount, 'semantic show');
          } else if (operation === 'prewarm-hit-one') {
            api.prewarmOne();
            expectActivationDelta(before, 1, 'prewarm');
            before = activationFlushes();
            const started = performance.now();
            api.showOne();
            sampleValues.push((performance.now() - started) * 1000);
            expectActivationDelta(before, 0, 'prewarmed show');
          } else if (operation === 'prewarm-hit-all') {
            api.prewarmAll();
            expectActivationDelta(before, setupInfo.rootCount, 'prewarm');
            before = activationFlushes();
            const started = performance.now();
            api.showAll();
            sampleValues.push((performance.now() - started) * 1000);
            expectActivationDelta(before, 0, 'prewarmed show');
          } else {
            throw new Error(`unknown operation: ${operation}`);
          }
        }
        const finalStats = api.stats();
        if (finalStats.inactiveSkippedFlushes < samples) {
          throw new Error(
            `inactive skip sanity check failed for ${operation}: saw ${finalStats.inactiveSkippedFlushes}`,
          );
        }
        return {
          system: 'incr_tea',
          suite: 'activation-trigger-overhead',
          operation,
          ownership,
          n: rootCount,
          workspaceSize: setupInfo.workspaceSize,
          inactiveUpdates,
          unit: 'us',
          samples: sampleValues,
          stats: finalStats,
        };
      } finally {
        api.dispose();
      }
    },
    { ownership, rootCount, operation, samples, inactiveUpdates, timeoutMs },
  );
}

function printReport({ browserVersion, userAgent, raw }) {
  const results = summarize(raw);
  const byKey = new Map(results.map(result => [keyOf(result), result]));
  const lines = [
    '# Incremental TEA activation-trigger overhead probe',
    '',
    'Measures IntersectionObserver callback dispatch, observer-triggered activation, direct manual activation, and the example-local manual-first policy helper accepted by the #280 ADR.',
    '',
    '## Environment',
    '',
    '| Field | Value |',
    '|---|---|',
    `| Browser | ${browserVersion} |`,
    `| User agent | ${userAgent.replaceAll('|', '\\|')} |`,
    `| Samples | ${samples} |`,
    `| Inactive updates before activation | ${inactiveUpdates} |`,
    '',
    '## Results (µs)',
    '',
  ];

  for (const ownership of ownerships) {
    lines.push(`### ${ownership}`, '', '#### Trigger and direct-activate controls', '', '| roots | observer dispatch | observer activate one | observer activate all | manual activate one | manual activate all |', '|---:|---:|---:|---:|---:|---:|');
    for (const rootCount of rootCounts) {
      const row = triggerOperations.map(operation => cell(byKey.get(`${ownership}:${rootCount}:${operation}`)));
      lines.push(`| ${rootCount} | ${row.join(' | ')} |`);
    }
    lines.push('', '#### Manual-first policy controller', '', '| roots | semantic show one | prewarm hit one | prewarm miss one | semantic show all | prewarm hit all | prewarm miss all |', '|---:|---:|---:|---:|---:|---:|---:|');
    for (const rootCount of rootCounts) {
      const row = policyOperations.map(operation => cell(byKey.get(`${ownership}:${rootCount}:${operation}`)));
      lines.push(`| ${rootCount} | ${row.join(' | ')} |`);
    }
    lines.push('');
  }

  lines.push(
    '## Notes',
    '',
    '- Observer-dispatch rows install one observer per root, reveal every root, and resolve when every observer callback has run.',
    '- Observer rows move hidden hosts from offscreen (`left:-10000px`) into the viewport to force an IntersectionObserver threshold crossing.',
    '- Manual rows use the same prepared inactive state and call `BrowserRenderer::activate` directly as the control baseline.',
    '- Policy rows use `BrowserRootActivationController`: semantic show is direct activation through the accepted helper, prewarm miss times show without an earlier prewarm, and prewarm hit performs prewarm before the timed semantic show.',
    '- `observer-activate-all` installs one observer per root and reveals all hosts in one DOM turn to expose browser callback batching/serialization behavior.',
    '',
    '<details><summary>Raw JSON</summary>',
    '',
    '```json',
    JSON.stringify(raw, null, 2),
    '```',
    '',
    '</details>',
  );

  console.log(lines.join('\n'));
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
  await page.waitForFunction(
    () => globalThis.__incrTeaActivationTriggerBench?.setup,
    undefined,
    { polling: 50 },
  );
  const userAgent = await page.evaluate(() => navigator.userAgent);

  const raw = [];
  for (const ownership of ownerships) {
    for (const rootCount of rootCounts) {
      for (const operation of operations) {
        raw.push(await measureCell(page, { ownership, rootCount, operation }));
      }
    }
  }

  printReport({ browserVersion: browser.version(), userAgent, raw });
} finally {
  if (browser) await browser.close();
  await close(server);
}
