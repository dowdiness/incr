import { execFileSync } from 'node:child_process';
import { writeFile } from 'node:fs/promises';
import { chromium } from 'playwright';
import { assert, close, createStaticServer, host, listen } from './browser-harness.mjs';

const warmup = positiveInt(process.env.MACHINE_COMPOSITION_WARMUP, 200);
const iterations = positiveInt(process.env.MACHINE_COMPOSITION_ITERATIONS, 1000);
const runCount = positiveInt(process.env.MACHINE_COMPOSITION_RUNS, 3);
const rawPath = process.env.MACHINE_COMPOSITION_RAW_PATH ??
  '/tmp/incr-machine-composition-raw.json';
const sizes = [64, 256];

function positiveInt(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? Math.trunc(parsed) : fallback;
}

function percentile(values, fraction) {
  const sorted = [...values].sort((left, right) => left - right);
  const index = Math.min(sorted.length - 1, Math.ceil(sorted.length * fraction) - 1);
  return sorted[index];
}

function summarize(records) {
  return {
    samples: records.length,
    flush_p50_us: percentile(records.map(record => record.flush_total_us), 0.5),
    flush_p95_us: percentile(records.map(record => record.flush_total_us), 0.95),
    transition_p50_us: percentile(records.map(record => record.transition_us), 0.5),
    transition_p95_us: percentile(records.map(record => record.transition_us), 0.95),
    view_p50_us: percentile(records.map(record => record.view_us), 0.5),
    view_p95_us: percentile(records.map(record => record.view_us), 0.95),
    dom_patch_p50_us: percentile(records.map(record => record.dom_patch_us), 0.5),
    dom_patch_p95_us: percentile(records.map(record => record.dom_patch_us), 0.95),
  };
}

function verifyRecords(records, childCount) {
  assert(records.length === iterations, `expected ${iterations} records at ${childCount}`);
  for (const record of records) {
    assert(record.child_count === childCount, 'record child count drifted');
    assert(record.transition_calls === 1, 'sample did not contain one transition');
    assert(record.view_calls === 1, 'sample did not contain one view projection');
    assert(record.patch_calls === 1, 'sample did not contain one DOM patch');
    assert(record.created_nodes === 0, 'local edit created a row');
    assert(record.removed_nodes === 0, 'local edit removed a row');
    assert(record.moved_nodes === 0, 'local edit moved a row');
    const targets = Object.keys(record.property_mutations_by_target);
    assert(
      targets.every(target => target === '0' || target === 'inspector'),
      `local edit mutated unrelated target ${targets.join(', ')}`,
    );
  }
}

const server = createStaticServer('/examples/incr_tea/ui-compare-bench.html');
await listen(server);
const address = server.address();
assert(address && typeof address !== 'string', 'machine composition server did not bind');
const browser = await chromium.launch({ headless: true });

try {
  const page = await browser.newPage();
  const pageErrors = [];
  page.on('pageerror', error => pageErrors.push(error.message));
  await page.goto(
    `http://${host}:${address.port}/examples/incr_tea/ui-compare-bench.html`,
    { waitUntil: 'load' },
  );
  await page.waitForFunction(
    () => globalThis.__incrTeaMachineComposition?.benchmark,
    undefined,
    { polling: 50 },
  );
  const installed = await page.evaluate(() =>
    typeof globalThis.__incrTeaMachineComposition === 'object',
  );
  assert(installed, `machine API failed to install: ${pageErrors.join('; ')}`);
  const runs = [];
  for (const childCount of sizes) {
    for (let run = 1; run <= runCount; run += 1) {
      const records = await page.evaluate(
        ({ childCount: n, warmup: w, iterations: count }) =>
          globalThis.__incrTeaMachineComposition.benchmark(n, w, count),
        { childCount, warmup, iterations },
      );
      verifyRecords(records, childCount);
      runs.push({ child_count: childCount, run, summary: summarize(records), records });
    }
  }

  const gateRuns = runs.filter(run => run.child_count === 256);
  const gatePassed = gateRuns.every(run => run.summary.flush_p95_us < 16_700);
  const metadata = {
    captured_at: new Date().toISOString(),
    host: `${process.platform} ${process.arch}`,
    node: process.version,
    chromium: browser.version(),
    moonbit: execFileSync('moon', ['version', '--all'], { encoding: 'utf8' }).trim(),
    warmup,
    iterations,
    run_count: runCount,
    gate: 'all 256-child runs have edit-to-flush p95 < 16700us',
    gate_passed: gatePassed,
  };
  await writeFile(rawPath, `${JSON.stringify({ metadata, runs }, null, 2)}\n`);
  console.log(JSON.stringify({
    metadata,
    summaries: runs.map(({ child_count, run, summary }) => ({
      child_count,
      run,
      ...summary,
    })),
    raw_path: rawPath,
  }, null, 2));
  assert(gatePassed, '256-child synchronous JS p95 gate failed');
} finally {
  await browser.close();
  await close(server);
}
