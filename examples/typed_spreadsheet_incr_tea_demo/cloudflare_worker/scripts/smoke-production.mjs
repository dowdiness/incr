const baseUrl = process.env.SMOKE_BASE_URL ?? process.env.BASE_URL;
if (!baseUrl) {
  throw new Error('Set SMOKE_BASE_URL to the deployed Worker URL.');
}

const base = new URL(baseUrl);
if (!['http:', 'https:'].includes(base.protocol)) {
  throw new Error(`SMOKE_BASE_URL must use http or https: ${baseUrl}`);
}
base.pathname = base.pathname.replace(/\/$/, '');

const sockets = new Set();

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function roomName(prefix) {
  return `${prefix}-${crypto.randomUUID().replaceAll('-', '')}`;
}

async function wait(milliseconds) {
  await new Promise(resolve => setTimeout(resolve, milliseconds));
}

async function retry(label, operation, attempts = 3) {
  let lastError;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      return await operation();
    } catch (error) {
      lastError = error;
      if (attempt < attempts) {
        console.warn(`retrying ${label} (${attempt}/${attempts - 1})`);
        await wait(1_000);
      }
    }
  }
  throw lastError;
}

async function checkHttp(pathname) {
  const response = await fetch(new URL(pathname, base), {
    headers: { Accept: 'text/html' },
  });
  assert(response.ok, `${pathname} returned ${response.status}`);
  return response;
}

async function openSocket(room) {
  const url = new URL(`/api/rooms/${room}`, base);
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
  const socket = new WebSocket(url);
  sockets.add(socket);
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`WebSocket open timeout: ${url}`)), 15_000);
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

function nextMessages(socket, count) {
  return new Promise((resolve, reject) => {
    const messages = [];
    const timer = setTimeout(() => reject(new Error(`Expected ${count} relay messages`)), 15_000);
    socket.addEventListener('message', event => {
      messages.push(event.data);
      if (messages.length === count) {
        clearTimeout(timer);
        resolve(messages);
      }
    });
  });
}

function waitForClose(socket) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('WebSocket close timeout')), 15_000);
    socket.addEventListener('close', event => {
      clearTimeout(timer);
      resolve(event);
    }, { once: true });
  });
}

async function testRelay() {
  const room = roomName('smoke-protocol');
  const first = await openSocket(room);
  const second = await openSocket(room);
  let senderMessages = 0;
  first.addEventListener('message', () => { senderMessages += 1; });
  const payload = JSON.stringify({
    schema: 1,
    kind: 'operation',
    operation_id: `smoke-${crypto.randomUUID()}`,
    payload: { cell: 'A1', value: '15' },
  });
  const received = nextMessages(second, 2);
  first.send(payload);
  first.send(payload);
  const messages = await received;
  assert(messages[0] === payload && messages[1] === payload, 'protocol payload changed or deduplicated');
  await wait(100);
  assert(senderMessages === 0, 'relay echoed a frame to the sender');
  first.close();
  second.close();
  console.log('✓ production protocol relay and duplicate delivery');
}

async function testRejectedFrames() {
  const binaryRoom = roomName('smoke-binary');
  const binarySender = await openSocket(binaryRoom);
  const binaryReceiver = await openSocket(binaryRoom);
  let binaryReceived = false;
  binaryReceiver.addEventListener('message', () => { binaryReceived = true; });
  const binaryClosed = waitForClose(binarySender);
  binarySender.send(new Uint8Array([0, 1, 2, 3]));
  assert((await binaryClosed).code === 1003, 'binary frame was not closed with 1003');
  await wait(100);
  assert(!binaryReceived, 'binary frame reached the peer');
  binaryReceiver.close();

  const oversizeRoom = roomName('smoke-oversize');
  const oversizeSender = await openSocket(oversizeRoom);
  const oversizeReceiver = await openSocket(oversizeRoom);
  let oversizeReceived = false;
  oversizeReceiver.addEventListener('message', () => { oversizeReceived = true; });
  const oversizeClosed = waitForClose(oversizeSender);
  oversizeSender.send('x'.repeat(256 * 1024 + 1));
  assert((await oversizeClosed).code === 1009, 'oversized frame was not closed with 1009');
  await wait(100);
  assert(!oversizeReceived, 'oversized frame reached the peer');
  oversizeReceiver.close();
  console.log('✓ production binary and oversized frame rejection');
}

async function testRateLimit() {
  const sender = await openSocket(roomName('smoke-rate'));
  const closed = waitForClose(sender);
  for (let index = 0; index < 61; index += 1) sender.send(`smoke-rate-${index}`);
  assert((await closed).code === 1013, 'rate limit was not enforced with 1013');
  console.log('✓ production per-connection rate limit');
}

try {
  const health = await fetch(new URL('/health', base));
  assert(health.status === 200, `/health returned ${health.status}`);
  console.log('✓ production health endpoint');

  for (const pathname of ['/', '/collab']) {
    const response = await checkHttp(pathname);
    const body = await response.text();
    assert(body.includes('<html'), `${pathname} did not return the SPA`);
    console.log(`✓ production SPA route ${pathname}`);
  }

  await retry('protocol relay', testRelay);
  await retry('frame rejection', testRejectedFrames);
  await retry('rate limit', testRateLimit);
  console.log(`Production smoke passed: ${base.origin}`);
} finally {
  for (const socket of sockets) {
    if (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING) {
      socket.close();
    }
  }
}
