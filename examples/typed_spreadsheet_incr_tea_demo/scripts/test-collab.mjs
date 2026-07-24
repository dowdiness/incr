import { chromium } from 'playwright';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const distRoot = resolve(fileURLToPath(new URL('../dist/', import.meta.url)));
const host = '127.0.0.1';

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function contentType(filePath) {
  switch (extname(filePath)) {
    case '.html': return 'text/html; charset=utf-8';
    case '.js': return 'text/javascript; charset=utf-8';
    case '.css': return 'text/css; charset=utf-8';
    default: return 'application/octet-stream';
  }
}

function filePathForRequest(pathname) {
  const localPath = pathname === '/' || pathname === '/collab'
    ? '/index.html'
    : decodeURIComponent(pathname);
  const filePath = resolve(distRoot, `.${localPath}`);
  assert(filePath === distRoot || filePath.startsWith(`${distRoot}${sep}`), `invalid path: ${pathname}`);
  return filePath;
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

const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url ?? '/', `http://${request.headers.host ?? host}`);
    const filePath = filePathForRequest(url.pathname);
    const bytes = await readFile(filePath);
    response.writeHead(200, { 'content-type': contentType(filePath) });
    response.end(bytes);
  } catch (error) {
    response.writeHead(404);
    response.end(error instanceof Error ? error.message : 'not found');
  }
});

await new Promise((resolveServer, reject) => {
  server.once('error', reject);
  server.listen(0, host, resolveServer);
});

let browser;
try {
  const address = server.address();
  assert(address && typeof address === 'object', 'server did not bind');
  const baseUrl = `http://${host}:${address.port}`;
  browser = await chromium.launch({ headless: process.env.HEADLESS !== '0' });
  const context = await browser.newContext();
  const hostPage = await context.newPage();
  const joinPage = await context.newPage();
  const invalidPage = await context.newPage();
  const pageErrors = [];
  hostPage.on('pageerror', error => pageErrors.push(`host: ${error.message}`));
  joinPage.on('pageerror', error => pageErrors.push(`join: ${error.message}`));
  invalidPage.on('pageerror', error => pageErrors.push(`invalid: ${error.message}`));

  const room = `proof-${Date.now()}`;
  await invalidPage.goto(`${baseUrl}/collab?role=host&room=&peer=invalid`, { waitUntil: 'load' });
  await invalidPage.waitForFunction(() => document.body.textContent?.includes('non-empty room'));
  assert(await invalidPage.locator('#cell-B1').count() === 0, 'invalid collab config bootstrapped a document');
  await invalidPage.close();
  console.log('✓ invalid collab config fails closed');

  await hostPage.goto(`${baseUrl}/collab?role=host&room=${room}&peer=host`, { waitUntil: 'load' });
  await hostPage.waitForSelector('#cell-B1');
  await waitForCellText(hostPage, 'B1', '11');
  await joinPage.goto(`${baseUrl}/collab?role=join&room=${room}&peer=join`, { waitUntil: 'load' });
  await joinPage.waitForSelector('#cell-B1');
  await waitForCellText(joinPage, 'B1', '11');
  assert(await hostPage.getByText('Reset unavailable in collaboration').count() === 1, 'host reset control remained active');
  assert(await joinPage.getByText('Reset unavailable in collaboration').count() === 1, 'join reset control remained active');
  console.log('✓ host bootstrap and join attach');

  await joinPage.evaluate(roomName => {
    const messages = [];
    const channel = new BroadcastChannel(`typed-sheet-collab/${roomName}`);
    channel.addEventListener('message', event => {
      try {
        const value = JSON.parse(String(event.data));
        if (Array.isArray(value) && value[1] === 'ops') messages.push(String(event.data));
      } catch {}
    });
    globalThis.__collabTestSpy = { channel, messages };
  }, room);

  await hostPage.locator('#cell-A1').click();
  await hostPage.locator('#formula-editor-input').fill('99');
  await waitForDraftText(hostPage, 'A1', '99');
  await waitForCellText(joinPage, 'A1', '10');
  await waitForCellText(joinPage, 'B1', '11');
  assert((await joinPage.locator('#cell-B1').getAttribute('class'))?.includes('selected'), 'host selection leaked to joiner');
  assert(await joinPage.evaluate(() => document.activeElement?.id !== 'formula-editor-input'), 'host focus leaked to joiner');
  console.log('✓ draft selection and focus remain local');

  await hostPage.locator('#formula-editor-input').fill('15');
  await waitForDraftText(hostPage, 'A1', '15');
  await hostPage.locator('.primary-action').click();
  await waitForCellText(hostPage, 'B1', '16');
  await waitForCellText(joinPage, 'A1', '15');
  await waitForCellText(joinPage, 'B1', '16');
  await joinPage.waitForFunction(() => globalThis.__collabTestSpy?.messages.length > 0);
  console.log('✓ host to join dependent update');

  const messagesBeforeReplay = await joinPage.evaluate(() => globalThis.__collabTestSpy.messages.length);
  await joinPage.evaluate(roomName => {
    const replay = new BroadcastChannel(`typed-sheet-collab/${roomName}`);
    replay.postMessage(globalThis.__collabTestSpy.messages.at(-1));
    replay.close();
  }, room);
  await joinPage.waitForTimeout(100);
  await waitForCellText(joinPage, 'A1', '15');
  await waitForCellText(joinPage, 'B1', '16');
  assert(
    await joinPage.evaluate(expected => globalThis.__collabTestSpy.messages.length === expected + 1, messagesBeforeReplay),
    'duplicate Ops caused a publication loop',
  );
  console.log('✓ duplicate Ops is idempotent and does not loop');

  await joinPage.locator('#cell-A1').click();
  await joinPage.locator('#formula-editor-input').fill('20');
  await waitForDraftText(joinPage, 'A1', '20');
  await joinPage.locator('.primary-action').click();
  await waitForCellText(joinPage, 'B1', '21');
  await waitForCellText(hostPage, 'A1', '20');
  await waitForCellText(hostPage, 'B1', '21');
  console.log('✓ join to host dependent update');

  await joinPage.evaluate(roomName => {
    const channel = new BroadcastChannel(`typed-sheet-collab/${roomName}`);
    channel.postMessage('{malformed');
    channel.close();
  }, room);
  await hostPage.waitForFunction(() => document.body.textContent?.includes('Malformed collaboration message'));
  assert(pageErrors.length === 0, `page errors after malformed injection: ${pageErrors.join('\n')}`);
  await hostPage.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pagehide')));
  const bodyAfterDispose = await hostPage.locator('body').textContent();
  await joinPage.evaluate(roomName => {
    const channel = new BroadcastChannel(`typed-sheet-collab/${roomName}`);
    channel.postMessage('{malformed-after-dispose');
    channel.close();
  }, room);
  await joinPage.waitForTimeout(50);
  assert(await hostPage.locator('body').textContent() === bodyAfterDispose, 'disposed host still handled channel input');
  assert(pageErrors.length === 0, `page errors after disposal: ${pageErrors.join('\n')}`);
  await joinPage.evaluate(() => globalThis.__collabTestSpy.channel.close());
  console.log('✓ malformed message and idempotent disposal');
} finally {
  if (browser) await browser.close();
  await new Promise(resolveServer => server.close(resolveServer));
}
