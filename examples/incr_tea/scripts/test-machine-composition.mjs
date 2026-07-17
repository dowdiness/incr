import { chromium } from 'playwright';
import { assert, close, createStaticServer, host, listen } from './browser-harness.mjs';

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
    () => globalThis.__incrTeaMachineComposition?.structural,
    undefined,
    { polling: 50 },
  );
  const installed = await page.evaluate(() => ({
    machine: typeof globalThis.__incrTeaMachineComposition,
    compare: typeof globalThis.__incrTeaUiCompareDomBench,
  }));
  assert(
    installed.machine === 'object',
    `machine API failed to install (${JSON.stringify(installed)}): ${pageErrors.join('; ')}`,
  );
  const result = await page.evaluate(() => globalThis.__incrTeaMachineComposition.structural(8));

  assert(result.edit_identity, 'local edit replaced a semantic row DOM node');
  assert(result.reorder_identity, 'reorder replaced a semantic row DOM node');
  assert(result.edit.created_nodes === 0, 'local edit created a keyed row');
  assert(result.edit.removed_nodes === 0, 'local edit removed a keyed row');
  assert(result.edit.moved_nodes === 0, 'local edit moved a keyed row');
  assert(result.reorder.created_nodes === 0, 'reorder created a keyed row');
  assert(result.reorder.removed_nodes === 0, 'reorder removed a keyed row');

  const editTargets = Object.keys(result.edit.property_mutations_by_target);
  assert(editTargets.includes('0'), 'local edit did not mutate the edited row');
  assert(editTargets.includes('inspector'), 'local edit did not update the inspector');
  assert(
    editTargets.every(target => target === '0' || target === 'inspector'),
    `local edit mutated an unrelated target: ${editTargets.join(', ')}`,
  );
  assert(result.edit.transition_calls === 1, 'local edit did not run one transition');
  assert(result.edit.view_calls === 1, 'local edit did not run one view projection');
  assert(result.edit.patch_calls === 1, 'local edit did not run one DOM patch');

  assert(result.stale.patch_calls === 0, 'stale completion attempted a DOM patch');
  assert(result.stale.created_nodes === 0, 'stale completion created a row');
  assert(result.stale.removed_nodes === 0, 'stale completion removed a row');
  assert(result.stale.moved_nodes === 0, 'stale completion moved a row');
  assert(
    Object.keys(result.stale.property_mutations_by_target).length === 0,
    'stale completion performed a DOM mutation',
  );

  assert(result.duplicate.patch_calls === 0, 'duplicate completion attempted a DOM patch');
  assert(result.duplicate.created_nodes === 0, 'duplicate completion created a row');
  assert(result.duplicate.removed_nodes === 0, 'duplicate completion removed a row');
  assert(result.duplicate.moved_nodes === 0, 'duplicate completion moved a row');
  assert(
    Object.keys(result.duplicate.property_mutations_by_target).length === 0,
    'duplicate completion performed a DOM mutation',
  );

  console.log(JSON.stringify(result, null, 2));
  console.log('machine composition structural browser checks passed');
} finally {
  await browser.close();
  await close(server);
}
