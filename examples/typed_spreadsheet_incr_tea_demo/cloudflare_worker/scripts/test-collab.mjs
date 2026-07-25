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

async function openWebSocket(url) {
  const socket = new WebSocket(url);
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`WebSocket open timeout: ${url}`)), 5000);
    socket.addEventListener('open', () => {
      clearTimeout(timer);
      resolve();
    }, { once: true });
    socket.addEventListener('error', () => {
      clearTimeout(timer);
      reject(new Error(`WebSocket open failed: ${url}`));
    }, { once: true });
  });
  return socket;
}

async function waitForClose(socket, expectedCode) {
  const code = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('WebSocket close timeout')), 5000);
    socket.addEventListener('close', event => {
      clearTimeout(timer);
      resolve(event.code);
    }, { once: true });
  });
  assert(code === expectedCode, `expected WebSocket close ${expectedCode}, got ${code}`);
}

async function waitForMessages(socket, expectedCount) {
  return new Promise((resolve, reject) => {
    const messages = [];
    const timer = setTimeout(() => reject(new Error(`expected ${expectedCount} relay messages`)), 5000);
    socket.addEventListener('message', event => {
      messages.push(event.data);
      if (messages.length === expectedCount) {
        clearTimeout(timer);
        resolve(messages);
      }
    });
  });
}

async function wait(milliseconds) {
  await new Promise(resolve => setTimeout(resolve, milliseconds));
}

async function testOpaqueProtocolRelay(baseUrl) {
  const room = `relay-protocol-${Date.now()}`;
  const url = `${baseUrl}/api/rooms/${room}`;
  const sender = await openWebSocket(url);
  const receiver = await openWebSocket(url);
  const senderMessages = [];
  sender.addEventListener('message', event => senderMessages.push(event.data));

  const protocolEnvelope = JSON.stringify({
    schema: 1,
    kind: 'operation',
    operation_id: 'duplicate-op-001',
    payload: { cell: 'A1', value: '15' },
  });
  const received = waitForMessages(receiver, 2);
  sender.send(protocolEnvelope);
  sender.send(protocolEnvelope);
  const messages = await received;

  assert(messages[0] === protocolEnvelope && messages[1] === protocolEnvelope, 'relay changed protocol payload');
  await wait(100);
  assert(senderMessages.length === 0, 'relay echoed a message back to its sender');
  sender.close();
  receiver.close();
  console.log('✓ opaque protocol frames and duplicate delivery are preserved');
}

async function testBinaryRelayRejection(baseUrl) {
  const room = `relay-binary-${Date.now()}`;
  const sender = await openWebSocket(`${baseUrl}/api/rooms/${room}`);
  const receiver = await openWebSocket(`${baseUrl}/api/rooms/${room}`);
  let received = false;
  receiver.addEventListener('message', () => { received = true; });
  sender.send(new Uint8Array([0, 1, 2, 3]));
  await waitForClose(sender, 1003);
  await wait(100);
  assert(!received, 'binary frame reached the peer');
  receiver.close();
  console.log('✓ binary frames are rejected without relay');
}

async function testOversizedRelayRejection(baseUrl) {
  const room = `relay-oversize-${Date.now()}`;
  const sender = await openWebSocket(`${baseUrl}/api/rooms/${room}`);
  const receiver = await openWebSocket(`${baseUrl}/api/rooms/${room}`);
  let received = false;
  receiver.addEventListener('message', () => { received = true; });
  sender.send('x'.repeat(256 * 1024 + 1));
  await waitForClose(sender, 1009);
  await wait(100);
  assert(!received, 'oversized frame reached the peer');
  receiver.close();
  console.log('✓ oversized frames are rejected without relay');
}

const worker = spawn(npm, ['run', 'dev', '--', '--port', String(port)], {
  cwd: root.pathname,
  stdio: 'ignore',
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

  if (process.env.JOIN_FIRST === '1') {
    await joinPage.goto(joinUrl, { waitUntil: 'load' });
    await wait(500);
    await hostPage.goto(hostUrl, { waitUntil: 'load' });
  } else {
    await hostPage.goto(hostUrl, { waitUntil: 'load' });
    await joinPage.goto(joinUrl, { waitUntil: 'load' });
  }
  await hostPage.waitForSelector('#cell-B1');
  await waitForCellText(hostPage, 'B1', '11');
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

  await hostContext.close();
  await joinContext.close();
  await testOpaqueProtocolRelay(baseUrl);
  await testBinaryRelayRejection(baseUrl);
  await testOversizedRelayRejection(baseUrl);
} finally {
  if (browser) await browser.close();
  if (worker.pid) {
    try { process.kill(-worker.pid, 'SIGTERM'); } catch {}
  }
}
