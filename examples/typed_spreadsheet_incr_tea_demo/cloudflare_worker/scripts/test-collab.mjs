import { chromium } from 'playwright';
import { spawn } from 'node:child_process';

const port = 8797;
const host = '127.0.0.1';
const root = new URL('..', import.meta.url);
const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function waitForHealth(baseUrl) {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    try {
      const response = await fetch(`${baseUrl}/health`);
      if (response.ok) return;
    } catch {}
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  throw new Error('Worker did not become ready');
}

async function waitForCellText(page, cell, expected) {
  await page.waitForFunction(({ id, text }) => {
    return document.getElementById(id)?.textContent?.trim() === text;
  }, { id: `cell-${cell}`, text: expected });
}

async function waitForDraftText(page, cell, expected) {
  await page.waitForFunction(({ id, text }) => {
    const context = globalThis.typedSpreadsheetAIContext?.();
    return context?.cells?.find(candidate => candidate.id === id)?.draft_text === text;
  }, { id: cell, text: expected });
}

const worker = spawn(npm, ['run', 'dev', '--', '--port', String(port)], {
  cwd: root.pathname,
  stdio: 'pipe',
  detached: true,
});
const baseUrl = `http://${host}:${port}`;
let browser;

try {
  await waitForHealth(baseUrl);
  const room = `typed-sheet-${Date.now()}`;
  const hostUrl = `${baseUrl}/collab?role=host&room=${room}&peer=host&transport=websocket`;
  const joinUrl = `${baseUrl}/collab?role=join&room=${room}&peer=join&transport=websocket`;

  browser = await chromium.launch({ headless: process.env.HEADLESS !== '0' });
  const hostContext = await browser.newContext();
  const joinContext = await browser.newContext();
  const hostPage = await hostContext.newPage();
  const joinPage = await joinContext.newPage();
  const pageErrors = [];
  hostPage.on('pageerror', error => pageErrors.push(`host: ${error.message}`));
  joinPage.on('pageerror', error => pageErrors.push(`join: ${error.message}`));

  await hostPage.goto(hostUrl, { waitUntil: 'load' });
  await hostPage.waitForSelector('#cell-B1');
  await waitForCellText(hostPage, 'B1', '11');

  await joinPage.goto(joinUrl, { waitUntil: 'load' });
  await joinPage.waitForSelector('#cell-B1');
  await waitForCellText(joinPage, 'B1', '11');
  console.log('✓ independent browser contexts host bootstrap and join attach');

  await hostPage.locator('#cell-A1').click();
  await hostPage.getByLabel('Formula text for A1').fill('99');
  await waitForDraftText(hostPage, 'A1', '99');
  await waitForCellText(joinPage, 'A1', '10');
  await waitForCellText(joinPage, 'B1', '11');
  assert(await joinPage.locator('#cell-B1').getAttribute('class').then(value => value?.includes('selected')), 'selection leaked to joiner');
  assert(await joinPage.evaluate(() => document.activeElement?.id !== 'formula-editor-input'), 'focus leaked to joiner');
  console.log('✓ drafts, selection, and focus remain local');

  await hostPage.getByLabel('Formula text for A1').fill('15');
  await hostPage.locator('.primary-action').click();
  await waitForCellText(hostPage, 'B1', '16');
  await waitForCellText(joinPage, 'A1', '15');
  await waitForCellText(joinPage, 'B1', '16');
  console.log('✓ host to join dependent update');

  await joinPage.locator('#cell-A1').click();
  await joinPage.getByLabel('Formula text for A1').fill('20');
  await joinPage.locator('.primary-action').click();
  await waitForCellText(joinPage, 'B1', '21');
  await waitForCellText(hostPage, 'A1', '20');
  await waitForCellText(hostPage, 'B1', '21');
  console.log('✓ join to host dependent update');

  await hostPage.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pagehide')));
  const bodyAfterDispose = await hostPage.locator('body').textContent();
  await joinPage.locator('#cell-A1').click();
  await joinPage.getByLabel('Formula text for A1').fill('25');
  await joinPage.locator('.primary-action').click();
  await waitForCellText(joinPage, 'B1', '26');
  await joinPage.waitForTimeout(100);
  assert(await hostPage.locator('body').textContent() === bodyAfterDispose, 'disposed host received a later update');
  assert(pageErrors.length === 0, `page errors: ${pageErrors.join('\n')}`);
  console.log('✓ disposal stops later remote updates without browser errors');
} finally {
  if (browser) await browser.close();
  if (worker.pid) {
    try { process.kill(-worker.pid, 'SIGTERM'); } catch {}
  }
}
