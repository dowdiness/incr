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
  browser = await chromium.launch({ headless: process.env.HEADLESS !== '0' });
  const hostContext = await browser.newContext();
  const joinContext = await browser.newContext();
  const hostPage = await hostContext.newPage();
  const joinPage = await joinContext.newPage();
  const pageErrors = [];
  hostPage.on('pageerror', error => pageErrors.push(`host: ${error.message}`));
  joinPage.on('pageerror', error => pageErrors.push(`join: ${error.message}`));

  await hostPage.goto(`${baseUrl}/collab`, { waitUntil: 'load' });
  await hostPage.getByRole('button', { name: 'Create room' }).click();
  const inviteUrl = await hostPage.locator('#room-invite-output').inputValue();
  const invite = new URL(inviteUrl);
  const room = invite.searchParams.get('room');
  const invitePeer = invite.searchParams.get('peer');
  assert(invite.origin === baseUrl, 'room chooser produced a foreign-origin invitation');
  assert(invite.pathname === '/collab', 'room chooser produced the wrong invitation path');
  assert(invite.searchParams.get('role') === 'join', 'room chooser invitation is not join-only');
  assert(invite.searchParams.get('transport') === 'websocket', 'room chooser invitation is not WebSocket-only');
  assert(room?.length === 32, 'room chooser did not produce the 192-bit capability shape');
  assert(/^[A-Za-z0-9_-]+$/u.test(room), 'room chooser capability is not URL-safe');
  assert(invitePeer, 'room chooser invitation is missing a peer id');
  await hostPage.getByRole('button', { name: 'Copy invite link' }).click();
  await hostPage.getByRole('button', { name: 'Copied' }).waitFor();
  console.log('✓ room chooser creates a URL-safe invitation and confirms copy');

  const openHost = async () => {
    await Promise.all([
      hostPage.waitForURL(url => url.searchParams.get('role') === 'host'),
      hostPage.getByRole('button', { name: 'Open room' }).click(),
    ]);
    const host = new URL(hostPage.url());
    assert(host.searchParams.get('room') === room, 'host opened a different room');
    assert(host.searchParams.get('transport') === 'websocket', 'host did not open WebSocket transport');
    assert(host.searchParams.get('peer') !== invitePeer, 'host and join invitation reused a peer id');
  };
  const joinFromChooser = async () => {
    await joinPage.goto(`${baseUrl}/collab`, { waitUntil: 'load' });
    await joinPage.locator('#room-join-input').fill(
      'https://attacker.example/collab?role=join&room=abcdefghijklmnopqrstuv&peer=join&transport=websocket',
    );
    await joinPage.getByRole('button', { name: 'Join room' }).click();
    assert(new URL(joinPage.url()).search === '', 'invalid invitation navigated away from the chooser');
    assert(await joinPage.locator('#room-join-error').textContent(), 'invalid invitation did not expose an error');
    assert(await joinPage.locator('#cell-B1').count() === 0, 'invalid invitation bootstrapped a document');
    await joinPage.locator('#room-join-input').fill(inviteUrl);
    await Promise.all([
      joinPage.waitForURL(url => url.searchParams.get('role') === 'join'),
      joinPage.locator('#room-join-input').press('Enter'),
    ]);
  };

  if (process.env.JOIN_FIRST === '1') {
    await joinFromChooser();
    await wait(500);
    await openHost();
  } else {
    await openHost();
    await joinFromChooser();
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

  await hostPage.getByRole('button', { name: '15', exact: true }).click();
  await waitForCellText(hostPage, 'A1', '15');
  await waitForCellText(hostPage, 'B1', '16');
  await waitForCellText(joinPage, 'A1', '15');
  await waitForCellText(joinPage, 'B1', '16');
  console.log('✓ example click applies immediately and publishes the dependent update');

  const hostTraceBeforeRemote = await hostPage.locator('#app-trace').textContent();
  const hostEvidenceBeforeRemote = await hostPage.locator('#app-evidence').textContent();
  await joinPage.locator('#cell-A1').click();
  await joinPage.getByLabel('Formula text for A1').fill('20');
  await joinPage.locator('.primary-action').click();
  await waitForCellText(joinPage, 'B1', '21');
  await waitForCellText(hostPage, 'A1', '20');
  await waitForCellText(hostPage, 'B1', '21');
  const hostTraceAfterRemote = await hostPage.locator('#app-trace').textContent();
  const hostEvidenceAfterRemote = await hostPage.locator('#app-evidence').textContent();
  assert(hostTraceAfterRemote !== hostTraceBeforeRemote, 'host trace did not update after remote commit');
  assert(hostEvidenceAfterRemote !== hostEvidenceBeforeRemote, 'host evidence did not update after remote commit');
  assert(hostTraceAfterRemote?.includes('Remote update'), 'host trace did not identify the remote update');
  assert(hostEvidenceAfterRemote?.includes('A1'), 'host evidence omitted the remote target');
  assert(hostEvidenceAfterRemote?.includes('B1'), 'host evidence omitted the recomputed dependent');
  console.log('✓ join to host dependent update refreshes host trace and evidence');

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
