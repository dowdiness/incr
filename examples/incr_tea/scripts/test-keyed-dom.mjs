import { chromium } from 'playwright';
import { assert, close, createStaticServer, host, listen } from './browser-harness.mjs';

const listRows = {
  selector: '#list-root .list-item',
  closest: '.list-item',
  snapshotStore: '__incrTeaKeyedDomSnapshots',
};
const editorRows = {
  selector: '#editor-projection-root .editor-row',
  closest: '.editor-row',
  snapshotStore: '__incrTeaEditorSnapshots',
};
const initialOrder = ['item-1', 'item-2', 'item-3'];
const initialEditorOrder = ['sem-module', 'sem-binding', 'sem-call'];
const cssEscape = globalThis.CSS?.escape ?? (value => {
  const string = String(value);
  let result = '';
  for (let index = 0; index < string.length; index += 1) {
    const codeUnit = string.charCodeAt(index);
    const char = string.charAt(index);
    if (codeUnit === 0) {
      result += '\uFFFD';
    } else if (
      (codeUnit >= 1 && codeUnit <= 31) ||
      codeUnit === 127 ||
      (index === 0 && codeUnit >= 48 && codeUnit <= 57) ||
      (index === 1 && codeUnit >= 48 && codeUnit <= 57 && string.charCodeAt(0) === 45)
    ) {
      result += `\\${codeUnit.toString(16)} `;
    } else if (index === 0 && string.length === 1 && codeUnit === 45) {
      result += `\\${char}`;
    } else if (
      codeUnit >= 128 ||
      codeUnit === 45 ||
      codeUnit === 95 ||
      (codeUnit >= 48 && codeUnit <= 57) ||
      (codeUnit >= 65 && codeUnit <= 90) ||
      (codeUnit >= 97 && codeUnit <= 122)
    ) {
      result += char;
    } else {
      result += `\\${char}`;
    }
  }
  return result;
});

function sameOrder(actual, expected) {
  return actual.length === expected.length && actual.every((key, index) => key === expected[index]);
}

async function gotoDemo(page, baseUrl) {
  await page.goto(`${baseUrl}/examples/incr_tea/index.html`, { waitUntil: 'load' });
  await page.waitForSelector(listRows.selector);
  await page.waitForSelector(editorRows.selector);
  await waitForKeys(page, listRows, initialOrder);
  await waitForKeys(page, editorRows, initialEditorOrder);
}

async function keysFor(page, config) {
  return page.$$eval(config.selector, rows => rows.map(row => row.getAttribute('data-semantic-id') ?? ''));
}

async function waitForKeys(page, config, expected) {
  await page.waitForFunction(({ selector, expectedKeys }) => {
    const keys = Array.from(document.querySelectorAll(selector)).map(row => (
      row.getAttribute('data-semantic-id') ?? ''
    ));
    return keys.length === expectedKeys.length && keys.every((key, index) => key === expectedKeys[index]);
  }, { selector: config.selector, expectedKeys: expected });
}

async function clickScopedButton(page, rootSelector, label, context) {
  await page.evaluate(({ selector, buttonLabel, buttonContext }) => {
    const button = Array.from(document.querySelectorAll(`${selector} button`))
      .find(candidate => candidate.textContent?.trim() === buttonLabel);
    if (!(button instanceof HTMLButtonElement)) {
      throw new Error(`missing ${buttonContext} button: ${buttonLabel}`);
    }
    button.click();
  }, { selector: rootSelector, buttonLabel: label, buttonContext: context });
}

async function clickListButton(page, label, expectedOrder) {
  await clickScopedButton(page, '#list-root', label, 'keyed-list');
  await waitForKeys(page, listRows, expectedOrder);
}

async function clickEditorButton(page, label, expectedOrder) {
  await clickScopedButton(page, '#editor-projection-root', label, 'semantic-editor');
  await waitForKeys(page, editorRows, expectedOrder);
}

async function captureKeyedRows(page, config, snapshotName) {
  await page.evaluate(({ name, selector, store }) => {
    const snapshots = globalThis[store] ??= new Map();
    const rows = new Map();
    for (const row of document.querySelectorAll(selector)) {
      const key = row.getAttribute('data-semantic-id') ?? '';
      if (key) rows.set(key, row);
    }
    snapshots.set(name, rows);
  }, { name: snapshotName, selector: config.selector, store: config.snapshotStore });
}

async function assertRowsMatchSnapshot(page, config, snapshotName, keys, context) {
  const mismatches = await page.evaluate(({ name, expectedKeys, selector, store }) => {
    const snapshots = globalThis[store];
    const snapshot = snapshots?.get(name);
    if (!snapshot) return expectedKeys.map(key => `${key}: missing snapshot`);
    const current = new Map();
    for (const row of document.querySelectorAll(selector)) {
      const key = row.getAttribute('data-semantic-id') ?? '';
      if (key) current.set(key, row);
    }
    return expectedKeys.filter(key => current.get(key) !== snapshot.get(key));
  }, {
    name: snapshotName,
    expectedKeys: keys,
    selector: config.selector,
    store: config.snapshotStore,
  });
  assert(
    mismatches.length === 0,
    `${context}: expected keyed rows to preserve DOM identity; mismatched keys: ${mismatches.join(', ')}`,
  );
}

function inputSelector(config, key) {
  return `${config.selector}[data-semantic-id=${cssEscape(key)}] input`;
}

async function fillKeyedInput(page, config, key, value) {
  await page.locator(inputSelector(config, key)).fill(value);
}

async function focusKeyedInput(page, config, key) {
  await page.locator(inputSelector(config, key)).focus();
}

async function keyedInputValue(page, config, key) {
  return page.locator(inputSelector(config, key)).inputValue();
}

async function notesByKey(page) {
  return page.$$eval(listRows.selector, rows => Object.fromEntries(rows.map(row => {
    const input = row.querySelector('input');
    return [
      row.getAttribute('data-semantic-id') ?? '',
      input instanceof HTMLInputElement ? input.value : '',
    ];
  })));
}

async function activeState(page, config) {
  return page.evaluate(({ closest }) => {
    const active = document.activeElement;
    const row = active?.closest?.(closest);
    return {
      tag: active?.tagName ?? null,
      key: row?.getAttribute('data-semantic-id') ?? null,
      value: active instanceof HTMLInputElement ? active.value : null,
      isBody: active === document.body,
    };
  }, { closest: config.closest });
}

async function frameFlushes(page) {
  return page.evaluate(() => {
    const text = document.querySelector('#render-stats')?.textContent ?? '';
    const match = text.match(/rAF flushes: (\d+)/);
    return match ? Number(match[1]) : 0;
  });
}

async function clickCounterButton(page, label) {
  await clickScopedButton(page, '#counter-root', label, 'counter');
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
    await captureKeyedRows(page, listRows, 'before-prepend');
    await clickListButton(page, 'prepend', ['item-4', 'item-1', 'item-2', 'item-3']);
    await assertRowsMatchSnapshot(page, listRows, 'before-prepend', initialOrder, 'after prepend');

    await gotoDemo(page, baseUrl);
    await captureKeyedRows(page, listRows, 'before-remove-first');
    await clickListButton(page, 'remove first', ['item-2', 'item-3']);
    await assertRowsMatchSnapshot(
      page,
      listRows,
      'before-remove-first',
      ['item-2', 'item-3'],
      'after remove first',
    );

    await gotoDemo(page, baseUrl);
    await captureKeyedRows(page, listRows, 'before-reverse');
    await clickListButton(page, 'reverse', ['item-3', 'item-2', 'item-1']);
    await assertRowsMatchSnapshot(page, listRows, 'before-reverse', initialOrder, 'after reverse');
  });

  await runTest('uncontrolled input values stay with keyed rows across reorder', async () => {
    await gotoDemo(page, baseUrl);
    await fillKeyedInput(page, listRows, 'item-1', 'alpha note');
    await fillKeyedInput(page, listRows, 'item-2', 'bravo note');
    await fillKeyedInput(page, listRows, 'item-3', 'charlie note');

    await clickListButton(page, 'reverse', ['item-3', 'item-2', 'item-1']);
    const notes = await notesByKey(page);
    assert(notes['item-1'] === 'alpha note', 'item-1 note did not follow its keyed row after reverse');
    assert(notes['item-2'] === 'bravo note', 'item-2 note did not follow its keyed row after reverse');
    assert(notes['item-3'] === 'charlie note', 'item-3 note did not follow its keyed row after reverse');
  });

  await runTest('focused keyed input survives an unchanged-list animation-frame flush', async () => {
    await gotoDemo(page, baseUrl);
    await focusKeyedInput(page, listRows, 'item-2');
    assert((await activeState(page, listRows)).key === 'item-2', 'setup failed to focus item-2 input');

    const beforeFlushes = await frameFlushes(page);
    await clickCounterButton(page, 'touch unread field');
    await page.waitForFunction(previous => {
      const text = document.querySelector('#render-stats')?.textContent ?? '';
      const match = text.match(/rAF flushes: (\d+)/);
      return match ? Number(match[1]) > previous : false;
    }, beforeFlushes);

    const active = await activeState(page, listRows);
    assert(
      active.key === 'item-2' && active.tag === 'INPUT',
      `focused keyed input should survive an unchanged-list flush; active=${JSON.stringify(active)}`,
    );
  });

  await runTest('controlled greet properties recover on unchanged animation-frame flush', async () => {
    await gotoDemo(page, baseUrl);
    const setup = await page.evaluate(() => {
      const input = document.querySelector('#greet-root .demo-input');
      const checkbox = document.querySelector('#greet-root .demo-checkbox');
      if (!(input instanceof HTMLInputElement)) throw new Error('missing greet text input');
      if (!(checkbox instanceof HTMLInputElement)) throw new Error('missing greet checkbox');
      input.focus();
      globalThis.__incrTeaGreetInputBefore = input;
      globalThis.__incrTeaGreetCheckboxBefore = checkbox;
      input.value = 'rejected';
      checkbox.checked = true;
      return { focused: document.activeElement === input };
    });
    assert(setup.focused, 'setup failed to focus greet input');

    const beforeFlushes = await frameFlushes(page);
    await clickCounterButton(page, 'touch unread field');
    await page.waitForFunction(previous => {
      const text = document.querySelector('#render-stats')?.textContent ?? '';
      const match = text.match(/rAF flushes: (\d+)/);
      return match ? Number(match[1]) > previous : false;
    }, beforeFlushes);

    const state = await page.evaluate(() => {
      const input = document.querySelector('#greet-root .demo-input');
      const checkbox = document.querySelector('#greet-root .demo-checkbox');
      return {
        sameInput: input === globalThis.__incrTeaGreetInputBefore,
        sameCheckbox: checkbox === globalThis.__incrTeaGreetCheckboxBefore,
        focused: document.activeElement === input,
        value: input instanceof HTMLInputElement ? input.value : null,
        checked: checkbox instanceof HTMLInputElement ? checkbox.checked : null,
      };
    });
    assert(
      state.sameInput && state.sameCheckbox && state.focused,
      `unchanged greet flush should preserve nodes and focus; state=${JSON.stringify(state)}`,
    );
    assert(
      state.value === '' && state.checked === false,
      `unchanged greet flush should restore controlled value/checked; state=${JSON.stringify(state)}`,
    );
  });
  await runTest('select, date, and range controls recover after equal-view flushes', async () => {
    await gotoDemo(page, baseUrl);
    const selectors = {
      select: '#greet-root select[data-form-control="select"]',
      date: '#greet-root input[data-form-control="date"]',
      range: '#greet-root input[data-form-control="range"]',
      touch: '#greet-root button[data-form-control="touch"]',
      add: '#greet-root button[data-form-control="add"]',
    };
    assert(await page.locator(selectors.select).inputValue() === 'beta', 'select initial value mismatch');
    assert(await page.locator(selectors.date).inputValue() === '2026-01-02', 'date initial value mismatch');
    assert(await page.locator(selectors.range).inputValue() === '50', 'range initial value mismatch');
    await page.selectOption(selectors.select, 'gamma');
    await page.waitForFunction(() => (
      document.querySelector('[data-form-control-state]')?.textContent?.includes('select=gamma') ?? false
    ));
    await page.evaluate(({ date, range }) => {
      const dateInput = document.querySelector(date);
      const rangeInput = document.querySelector(range);
      if (!(dateInput instanceof HTMLInputElement) || !(rangeInput instanceof HTMLInputElement)) {
        throw new Error('missing date/range controls');
      }
      dateInput.value = '2026-02-03';
      dateInput.dispatchEvent(new Event('change', { bubbles: true }));
      rangeInput.value = '75';
      rangeInput.dispatchEvent(new Event('change', { bubbles: true }));
    }, selectors);
    await page.waitForFunction(() => {
      const state = document.querySelector('[data-form-control-state]')?.textContent ?? '';
      return state.includes('date=2026-02-03') && state.includes('range=75');
    });
    await page.locator(selectors.add).click();
    await page.waitForFunction(() => (
      document.querySelector('[data-form-control-state]')?.textContent?.includes('select=delta') ?? false
    ));
    assert(await page.locator(selectors.select).inputValue() === 'delta', 'new controlled option was not selected');


    const before = await page.evaluate(({ select, date, range }) => {
      const nodes = {
        select: document.querySelector(select),
        date: document.querySelector(date),
        range: document.querySelector(range),
      };
      if (
        !(nodes.select instanceof HTMLSelectElement) ||
        !(nodes.date instanceof HTMLInputElement) ||
        !(nodes.range instanceof HTMLInputElement)
      ) throw new Error('missing controlled form controls');
      nodes.select.value = 'alpha';
      nodes.date.value = '2026-01-02';
      nodes.range.value = '50';
      globalThis.__incrTeaFormNodesBefore = nodes;
      return { select: nodes.select.value, date: nodes.date.value, range: nodes.range.value };
    }, selectors);
    assert(
      before.select === 'alpha' && before.date === '2026-01-02' && before.range === '50',
      `setup failed to create form-control drift: ${JSON.stringify(before)}`,
    );

    const beforeFlushes = await frameFlushes(page);
    await page.locator(selectors.touch).click();
    await page.waitForFunction(previous => {
      const text = document.querySelector('#render-stats')?.textContent ?? '';
      const match = text.match(/rAF flushes: (\d+)/);
      return match ? Number(match[1]) > previous : false;
    }, beforeFlushes);

    const after = await page.evaluate(({ select, date, range }) => {
      const nodes = {
        select: document.querySelector(select),
        date: document.querySelector(date),
        range: document.querySelector(range),
      };
      return {
        sameSelect: nodes.select === globalThis.__incrTeaFormNodesBefore.select,
        sameDate: nodes.date === globalThis.__incrTeaFormNodesBefore.date,
        sameRange: nodes.range === globalThis.__incrTeaFormNodesBefore.range,
        select: nodes.select instanceof HTMLSelectElement ? nodes.select.value : null,
        date: nodes.date instanceof HTMLInputElement ? nodes.date.value : null,
        range: nodes.range instanceof HTMLInputElement ? nodes.range.value : null,
      };
    }, selectors);
    assert(
      after.sameSelect && after.sameDate && after.sameRange,
      `equal-view form flush replaced controlled nodes: ${JSON.stringify(after)}`,
    );
    assert(
      after.select === 'delta' && after.date === '2026-02-03' && after.range === '75',
      `equal-view form flush did not restore controlled values: ${JSON.stringify(after)}`,
    );
  });

  await runTest('focused keyed input loses focus when its keyed row is removed', async () => {
    await gotoDemo(page, baseUrl);
    await captureKeyedRows(page, listRows, 'before-focus-remove');
    await focusKeyedInput(page, listRows, 'item-1');
    assert((await activeState(page, listRows)).key === 'item-1', 'setup failed to focus item-1 input');

    await clickListButton(page, 'remove first', ['item-2', 'item-3']);
    await assertRowsMatchSnapshot(
      page,
      listRows,
      'before-focus-remove',
      ['item-2', 'item-3'],
      'after removing focused row',
    );
    const active = await activeState(page, listRows);
    assert(
      active.key === null && active.isBody,
      `expected focus to leave the list after removing the focused keyed row; active=${JSON.stringify(active)}`,
    );
  });

  await runTest('semantic editor keys survive position changes', async () => {
    await gotoDemo(page, baseUrl);
    await captureKeyedRows(page, editorRows, 'before-editor-move');
    await clickEditorButton(page, 'move selected down', ['sem-module', 'sem-call', 'sem-binding']);
    await assertRowsMatchSnapshot(
      page,
      editorRows,
      'before-editor-move',
      initialEditorOrder,
      'after moving selected semantic row',
    );
    const order = await keysFor(page, editorRows);
    assert(
      sameOrder(order, ['sem-module', 'sem-call', 'sem-binding']),
      `semantic editor order mismatch after move: ${JSON.stringify(order)}`,
    );
  });

  await runTest('semantic editor controlled input patches dirty value property', async () => {
    await gotoDemo(page, baseUrl);
    await captureKeyedRows(page, editorRows, 'before-editor-edit');
    await focusKeyedInput(page, editorRows, 'sem-binding');
    assert((await activeState(page, editorRows)).key === 'sem-binding', 'setup failed to focus sem-binding input');

    await fillKeyedInput(page, editorRows, 'sem-binding', 'fold');
    await page.waitForFunction(() => (
      document.querySelector('#editor-inspector-root')?.textContent?.includes('text: fold') ?? false
    ));
    await assertRowsMatchSnapshot(
      page,
      editorRows,
      'before-editor-edit',
      initialEditorOrder,
      'after local semantic text edit',
    );
    const active = await activeState(page, editorRows);
    assert(
      active.key === 'sem-binding' && active.tag === 'INPUT' && active.value === 'fold',
      `focused semantic input should survive local keyed edit; active=${JSON.stringify(active)}`,
    );

    await clickEditorButton(page, 'rename selected', initialEditorOrder);
    await page.waitForFunction(() => (
      document.querySelector('#editor-inspector-root')?.textContent?.includes('text: map') ?? false
    ));
    const renamedValue = await keyedInputValue(page, editorRows, 'sem-binding');
    assert(
      renamedValue === 'map',
      `controlled editor input should patch live value property after non-input rename; value=${renamedValue}`,
    );
  });

  const finalOrder = await keysFor(page, listRows);
  assert(sameOrder(finalOrder, initialOrder), 'final keyed-list order sanity check failed');
  assert(pageErrors.length === 0, `page error: ${pageErrors[0]?.stack ?? pageErrors[0]?.message}`);
} finally {
  if (browser) await browser.close();
  await close(server);
}
