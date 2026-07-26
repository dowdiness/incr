# Typed spreadsheet Cloudflare Worker

Production implementation skeleton for Issue #425.

This phase verifies the Worker → Durable Object boundary, static SPA assets,
and a two-connection opaque text relay. The Worker routes `/health`,
`/api/rooms/<capability>`, `/`, and `/collab`; the Durable Object accepts
Hibernation WebSockets, excludes the sender, limits the room to two connections,
and rejects oversized text frames. The static `/collab` route creates and joins
rooms entirely in the browser; it does not call a room-creation endpoint.
Per-connection rate metadata is stored in WebSocket Hibernation attachments,
and room admission is limited to 30 requests
per connecting IP per 60 seconds by a Cloudflare Rate Limit binding. The Worker
also validates canonical URL-safe room capabilities and same-site origins. Spreadsheet protocol and browser
provider selection remain outside the Worker relay.

## Run locally

```bash
npm install
npm run dev
```

Run the local Worker and Durable Object checks with:

```bash
npm run test:hibernation
npm run test:e2e
SMOKE_BASE_URL=https://your-worker.example.workers.dev npm run smoke:production
```

`test:hibernation` uses the Workers Vitest runtime eviction helper to hibernate
connected WebSockets, then verifies that messages still relay and the
attachment-backed rate limit survives the Durable Object restart.

`smoke:production` is a non-persistent deployment check: it uses random
transient room capabilities and sends bounded test frames to verify health, SPA
routes, protocol/duplicate relay, binary and oversized-frame rejection, and the
deployed rate limit.

The generated MoonBit module is loaded by `entry.mjs`. Cloudflare's Worker and
Durable Object exports remain the only JavaScript adapter surface.

For deployment, configure the `cloudflare-worker` GitHub environment with
`CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`, plus the environment variable
`CLOUDFLARE_WORKER_URL` containing the deployed Worker URL. The workflow deploys
the Worker and its static assets with Wrangler, then runs the production smoke
test against that URL.

## Capability threat model

The room capability is a bearer credential, not a user identity. Possession of
the capability grants access to one transient two-peer relay: a holder can read
and submit opaque protocol frames, but cannot access another room without its
capability. The Worker and Durable Object can see plaintext frames; this design
does not provide end-to-end encryption, membership, revocation, accounts, or
audit identity.

The production configuration explicitly keeps the stable `workers.dev` URL,
disables versioned Preview URLs, and enables full Worker observability logs.
Because request URLs can contain room capabilities, treat the Cloudflare
observability/logs account as security-sensitive and restrict access to it.
The Worker does not log protocol payloads or capability values itself.

Incident response, rollback, and capability-disclosure procedures are fixed in
[OPERATIONS.md](OPERATIONS.md).

The capability contract is:

- use a cryptographically random, URL-safe value with at least 22 characters
  (the smoke tests use a random UUID-derived value);
- treat the capability as secret even though the Worker only validates its
  format and length—format validation cannot prove entropy;
- share it only over a trusted channel and never use predictable examples such
  as `demo` in a deployed room;
- assume it can appear in browser history, the room URL, and edge access logs;
  do not use this transport for documents whose confidentiality requires
  revocation or a user access list.

Browser admission is same-site rather than strict same-Origin matching. The
following are accepted:

- an empty Origin, for non-browser WebSocket clients whose capability is the
  bearer check;
- an Origin exactly equal to the request URL origin;
- `http://localhost:8787` paired with `http://127.0.0.1:8787`, or the reverse,
  for local development.

An Origin such as `https://attacker.example` or a loopback origin with a
mismatched port such as `http://127.0.0.1:1` is rejected. Origin is CSRF
protection, not authentication. The relay limits exposure with two live
connections per room, bounded frame size, per-connection rate limiting, a
per-IP room-admission limiter, opaque forwarding, and no document persistence.

This threat model is accepted for the Issue #425 no-account, no-persistence
preview scope. Adding accounts, revocation, sensitive-document confidentiality,
or durable sharing requires a new capability exchange and authorization design;
it must not be treated as a small validation change.
