import { listDurableObjectIds, SELF, env } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';

const origin = 'https://typed-spreadsheet-cloudflare-worker.example';

function roomName() {
  return `admission-${crypto.randomUUID().replaceAll('-', '')}`;
}

async function fetchRoom(room, init = {}) {
  return SELF.fetch(new Request(
    `${origin}/api/rooms/${room}`,
    { headers: { Origin: origin, Upgrade: 'websocket' }, ...init },
  ));
}

async function assertRejectedWithoutCreatingRoom(request) {
  const before = await listDurableObjectIds(env.ROOMS);
  const response = await SELF.fetch(request);
  const after = await listDurableObjectIds(env.ROOMS);
  expect(response.status).toBe(400);
  expect(after.length).toBe(before.length);
  return response.text();
}

describe('Worker room admission boundary', () => {
  it('rejects non-upgrade requests before Durable Object lookup', async () => {
    const room = roomName();
    const body = await assertRejectedWithoutCreatingRoom(
      new Request(`${origin}/api/rooms/${room}`, {
        headers: { Origin: origin },
      }),
    );
    expect(body).toContain('websocket upgrade');
  });

  it('rejects invalid method, Origin, and capability before Durable Object lookup', async () => {
    const room = roomName();
    const methodBody = await assertRejectedWithoutCreatingRoom(
      new Request(`${origin}/api/rooms/${room}`, {
        method: 'POST',
        headers: { Origin: origin },
      }),
    );
    expect(methodBody).toContain('requires GET');

    const originBody = await assertRejectedWithoutCreatingRoom(
      new Request(`${origin}/api/rooms/${room}`, {
        headers: { Origin: 'https://attacker.example', Upgrade: 'websocket' },
      }),
    );
    expect(originBody).toContain('origin is not allowed');

    const capabilityBody = await assertRejectedWithoutCreatingRoom(
      new Request(`${origin}/api/rooms/too-short`, {
        headers: { Origin: origin, Upgrade: 'websocket' },
      }),
    );
    expect(capabilityBody).toContain('too short');
  });

  it('keeps valid upgrade admission available', async () => {
    const room = roomName();
    const response = await fetchRoom(room);
    expect(response.status).toBe(101);
    response.webSocket.accept();
    response.webSocket.close();
  });
});
