import { evictDurableObject } from 'cloudflare:test';
import { env, exports } from 'cloudflare:workers';
import { afterEach, describe, expect, it } from 'vitest';

const origin = 'http://example.com';
const sockets = [];

async function openRoomSocket(room) {
  const response = await exports.default.fetch(
    new Request(`${origin}/api/rooms/${room}`, {
      headers: {
        Origin: origin,
        Upgrade: 'websocket',
      },
    }),
  );
  expect(response.status).toBe(101);
  const socket = response.webSocket;
  expect(socket).toBeTruthy();
  socket.accept();
  sockets.push(socket);
  return socket;
}

function nextMessage(socket) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('WebSocket message timeout')), 5_000);
    socket.addEventListener('message', event => {
      clearTimeout(timer);
      resolve(event.data);
    }, { once: true });
  });
}

function messageCount(socket, expected) {
  return new Promise((resolve, reject) => {
    let count = 0;
    const timer = setTimeout(() => reject(new Error('WebSocket message count timeout')), 5_000);
    socket.addEventListener('message', () => {
      count += 1;
      if (count === expected) {
        clearTimeout(timer);
        resolve();
      }
    });
  });
}

function closeCode(socket) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('WebSocket close timeout')), 5_000);
    socket.addEventListener('close', event => {
      clearTimeout(timer);
      resolve(event.code);
    }, { once: true });
  });
}

afterEach(() => {
  while (sockets.length > 0) sockets.pop().close();
});

describe('Durable Object WebSocket hibernation', () => {
  it('keeps connected peers usable after eviction and restores attachment state', async () => {
    const room = `hibernation-${crypto.randomUUID().replaceAll('-', '')}`;
    const sender = await openRoomSocket(room);
    const receiver = await openRoomSocket(room);

    const beforeEviction = nextMessage(receiver);
    sender.send('before-eviction');
    await expect(beforeEviction).resolves.toBe('before-eviction');

    await evictDurableObject(env.ROOMS.getByName(room), { webSockets: 'hibernate' });

    const afterEviction = nextMessage(receiver);
    sender.send('after-eviction');
    await expect(afterEviction).resolves.toBe('after-eviction');

    const remainingMessages = messageCount(receiver, 58);
    for (let index = 0; index < 58; index += 1) sender.send(`quota-${index}`);
    await remainingMessages;

    await evictDurableObject(env.ROOMS.getByName(room), { webSockets: 'hibernate' });
    const closed = closeCode(sender);
    sender.send('quota-exceeded-after-eviction');
    await expect(closed).resolves.toBe(1013);
  });
});
