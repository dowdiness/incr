import { chromium } from 'playwright';
import { assert, close, createStaticServer, host, listen } from './browser-harness.mjs';

const initialOrder = ['item-1', 'item-2', 'item-3'];

function sameOrder(actual, expected) {
  return actual.length === expected.length && actual.every((key, index) => key === expected[index]);
}

async function gotoDemo(page, baseUrl) {
  await page.goto(`${baseUrl}/examples/incr_tea/index.html`, { waitUntil: 'load' });
  await page.waitForSelector('#list-root .list-item');
  await waitForOrder(page, initialOrder);
}

async function rowKeys(page) {
  return page.$$eval('#list-root .list-item', rows => rows.map(row => {
    const match = row.textContent?.match(/\((item-\d+)\)/);
    return match?.[1] ?? '';
  }));
}

async function waitForOrder(page, expected) {
  await page.waitForFunction(expectedKeys => {
    const keys = Array.from(document.querySelectorAll('#list-root .list-item')).map(row => {
      const match = row.textContent?.match(/\((item-\d+)\)/);
      return match?.[1] ?? '';
    });
    return keys.length === expectedKeys.length && keys.every((key, index) => key === expectedKeys[index]);
  }, expected);
}

async function clickListButton(page, label, expectedOrder) {
  await page.evaluate(buttonLabel => {
    const button = Array.from(document.querySelectorAll('#list-root button'))
      .find(candidate => candidate.textContent?.trim() === buttonLabel);
    if (!(button instanceof HTMLButtonElement)) {
      throw new Error(`missing keyed-list button: ${buttonLabel}`);
    }
    button.click();
  }, label);
  await waitForOrder(page, expectedOrder);
}

async function captureRows(page, snapshotName) {
  await page.evaluate(name => {
    const snapshots = globalThis.__incrTeaKeyedDomSnapshots ??= new Map();
    const rows = new Map();
    for (const row of document.querySelectorAll('#list-root .list-item')) {
      const match = row.textContent?.match(/\((item-\d+)\)/);
      if (match) rows.set(match[1], row);
    }
    snapshots.set(name, rows);
  }, snapshotName);
}

async function assertRowsMatchSnapshot(page, snapshotName, keys, context) {
  const mismatches = await page.evaluate(({ name, expectedKeys }) => {
    const snapshots = globalThis.__incrTeaKeyedDomSnapshots;
    const snapshot = snapshots?.get(name);
    if (!snapshot) return expectedKeys.map(key => `${key}: missing snapshot`);
    const current = new Map();
    for (const row of document.querySelectorAll('#list-root .list-item')) {
      const match = row.textContent?.match(/\((item-\d+)\)/);
      if (match) current.set(match[1], row);
    }
    return expectedKeys.filter(key => current.get(key) !== snapshot.get(key));
  }, { name: snapshotName, expectedKeys: keys });
  assert(
    mismatches.length === 0,
    `${context}: expected keyed rows to preserve DOM identity; mismatched keys: ${mismatches.join(', ')}`,
  );
}

async function fillNote(page, key, value) {
  await page.locator('#list-root .list-item')
    .filter({ hasText: `(${key})` })
    .locator('input')
    .fill(value);
}

async function notesByKey(page) {
  return page.$$eval('#list-root .list-item', rows => Object.fromEntries(rows.map(row => {
    const match = row.textContent?.match(/\((item-\d+)\)/);
    const input = row.querySelector('input');
    return [match?.[1] ?? '', input instanceof HTMLInputElement ? input.value : ''];
  })));
}

async function focusNote(page, key) {
  await page.evaluate(focusKey => {
    const row = Array.from(document.querySelectorAll('#list-root .list-item'))
      .find(candidate => candidate.textContent?.includes(`(${focusKey})`));
    const input = row?.querySelector('input');
    if (!(input instanceof HTMLInputElement)) {
      throw new Error(`missing keyed-list input: ${focusKey}`);
    }
    input.focus();
  }, key);
}

async function activeElementState(page) {
  return page.evaluate(() => {
    const active = document.activeElement;
    const row = active?.closest?.('.list-item');
    const match = row?.textContent?.match(/\((item-\d+)\)/);
    return {
      tag: active?.tagName ?? null,
      key: match?.[1] ?? null,
      value: active instanceof HTMLInputElement ? active.value : null,
      isBody: active === document.body,
    };
  });
}

async function frameFlushes(page) {
  return page.evaluate(() => {
    const text = document.querySelector('#render-stats')?.textContent ?? '';
    const match = text.match(/rAF flushes: (\d+)/);
    return match ? Number(match[1]) : 0;
  });
}

async function clickCounterButton(page, label) {
  await page.evaluate(buttonLabel => {
    const button = Array.from(document.querySelectorAll('#counter-root button'))
      .find(candidate => candidate.textContent?.trim() === buttonLabel);
    if (!(button instanceof HTMLButtonElement)) {
      throw new Error(`missing counter button: ${buttonLabel}`);
    }
    button.click();
  }, label);
}

async function runTest(name, fn) {
  await fn();
  console.log(`✓ ${name}`);
}

const server = createStaticServer('/examples/incr_tea/index.html');
await listen(server);

let browser;
try {
  const address = server.address();
  assert(address && typeof address === 'object', 'Test server did not bind to a TCP port');
  const baseUrl = `http://${host}:${address.port}`;

  browser = await chromium.launch({ headless: process.env.HEADLESS !== '0' });
  const page = await browser.newPage();
  const pageErrors = [];
  page.on('pageerror', error => pageErrors.push(error));

  await runTest('keyed row DOM identity survives prepend, remove-first, and reverse', async () => {
    await gotoDemo(page, baseUrl);
    await captureRows(page, 'before-prepend');
    await clickListButton(page, 'prepend', ['item-4', 'item-1', 'item-2', 'item-3']);
    await assertRowsMatchSnapshot(page, 'before-prepend', initialOrder, 'after prepend');

    await gotoDemo(page, baseUrl);
    await captureRows(page, 'before-remove-first');
    await clickListButton(page, 'remove first', ['item-2', 'item-3']);
    await assertRowsMatchSnapshot(
      page,
      'before-remove-first',
      ['item-2', 'item-3'],
      'after remove first',
    );

    await gotoDemo(page, baseUrl);
    await captureRows(page, 'before-reverse');
    await clickListButton(page, 'reverse', ['item-3', 'item-2', 'item-1']);
    await assertRowsMatchSnapshot(page, 'before-reverse', initialOrder, 'after reverse');
  });

  await runTest('uncontrolled input values stay with keyed rows across reorder', async () => {
    await gotoDemo(page, baseUrl);
    await fillNote(page, 'item-1', 'alpha note');
    await fillNote(page, 'item-2', 'bravo note');
    await fillNote(page, 'item-3', 'charlie note');

    await clickListButton(page, 'reverse', ['item-3', 'item-2', 'item-1']);
    const notes = await notesByKey(page);
    assert(notes['item-1'] === 'alpha note', 'item-1 note did not follow its keyed row after reverse');
    assert(notes['item-2'] === 'bravo note', 'item-2 note did not follow its keyed row after reverse');
    assert(notes['item-3'] === 'charlie note', 'item-3 note did not follow its keyed row after reverse');
  });

  await runTest('focused keyed input survives an unchanged-list animation-frame flush', async () => {
    await gotoDemo(page, baseUrl);
    await focusNote(page, 'item-2');
    assert((await activeElementState(page)).key === 'item-2', 'setup failed to focus item-2 input');

    const beforeFlushes = await frameFlushes(page);
    await clickCounterButton(page, 'touch unread field');
    await page.waitForFunction(previous => {
      const text = document.querySelector('#render-stats')?.textContent ?? '';
      const match = text.match(/rAF flushes: (\d+)/);
      return match ? Number(match[1]) > previous : false;
    }, beforeFlushes);

    const active = await activeElementState(page);
    assert(
      active.key === 'item-2' && active.tag === 'INPUT',
      `focused keyed input should survive an unchanged-list flush; active=${JSON.stringify(active)}`,
    );
  });

  await runTest('current all-reappend keyed applier drops focus when a focused survivor is re-appended', async () => {
    await gotoDemo(page, baseUrl);
    await captureRows(page, 'before-focus-reverse');
    await focusNote(page, 'item-2');
    assert((await activeElementState(page)).key === 'item-2', 'setup failed to focus item-2 input');

    await clickListButton(page, 'reverse', ['item-3', 'item-2', 'item-1']);
    await assertRowsMatchSnapshot(
      page,
      'before-focus-reverse',
      initialOrder,
      'after reverse with focused survivor',
    );
    const active = await activeElementState(page);
    assert(
      active.key === null && active.isBody,
      `expected current all-reappend limitation to drop focus; update this baseline when minimal moves preserve it. active=${JSON.stringify(active)}`,
    );
  });

  const finalOrder = await rowKeys(page);
  assert(sameOrder(finalOrder, ['item-3', 'item-2', 'item-1']), 'final keyed-list order sanity check failed');
  assert(pageErrors.length === 0, `page error: ${pageErrors[0]?.stack ?? pageErrors[0]?.message}`);
} finally {
  if (browser) await browser.close();
  await close(server);
}
