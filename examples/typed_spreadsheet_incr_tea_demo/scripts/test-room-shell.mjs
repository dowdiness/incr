import { webcrypto } from 'node:crypto';
import {
  buildWebSocketCollabUrl,
  generateCapability,
  normalizeInviteUrl,
} from '../src/collab-room-shell.js';

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

let requestedBytes = 0;
const deterministicCrypto = {
  getRandomValues(bytes) {
    requestedBytes = bytes.length;
    for (let index = 0; index < bytes.length; index += 1) bytes[index] = index;
    return bytes;
  },
};
const capability = generateCapability(deterministicCrypto);
assert(requestedBytes === 24, 'capability generation requested the wrong entropy boundary');
assert(capability.length === 32, '24 random bytes did not produce 32 base64url characters');
assert(/^[A-Za-z0-9_-]{32}$/u.test(capability), 'capability is not unpadded base64url');
assert(generateCapability(webcrypto) !== generateCapability(webcrypto), 'independent capabilities unexpectedly matched');
console.log('✓ capability generation uses 192 random bits and URL-safe output');

const base = 'https://sheet.example/collab';
const invite = buildWebSocketCollabUrl('join', capability, 'peer-id', base);
const parsed = new URL(invite);
assert(parsed.origin === 'https://sheet.example', 'invitation changed origin');
assert(parsed.pathname === '/collab', 'invitation changed path');
assert(parsed.searchParams.get('role') === 'join', 'invitation lost join role');
assert(parsed.searchParams.get('room') === capability, 'invitation lost room capability');
assert(parsed.searchParams.get('peer') === 'peer-id', 'invitation lost peer id');
assert(parsed.searchParams.get('transport') === 'websocket', 'invitation lost websocket transport');
console.log('✓ canonical WebSocket invitation URL contains the startup contract');

assert(normalizeInviteUrl(invite, base) === `${parsed.pathname}${parsed.search}`, 'same-origin invite was rejected');
assert(normalizeInviteUrl('/collab?role=join', base) === '/collab?role=join', 'relative same-origin invite was rejected');
assert(normalizeInviteUrl('https://attacker.example/collab?role=join', base) === '', 'foreign-origin invite was accepted');
assert(normalizeInviteUrl('https://user@sheet.example/collab?role=join', base) === '', 'credential-bearing invite was accepted');
assert(normalizeInviteUrl('https://sheet.example/collab?role=join#secret', base) === '', 'fragment-bearing invite was accepted');
assert(normalizeInviteUrl('not a URL', base) === '/not%20a%20URL', 'URL normalization semantics changed unexpectedly');
console.log('✓ invite normalization rejects unsafe origins, credentials, and fragments');
