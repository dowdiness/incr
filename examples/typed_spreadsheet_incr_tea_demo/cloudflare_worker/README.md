# Typed spreadsheet Cloudflare Worker

Production implementation skeleton for Issue #425.

This phase verifies the Worker → Durable Object boundary, static SPA assets,
and a two-connection opaque text relay. The Worker routes `/health`,
`/api/rooms/<capability>`, `/`, and `/collab`; the Durable Object accepts
Hibernation WebSockets, excludes the sender, limits the room to two connections,
and rejects oversized text frames. Per-connection rate metadata is stored in
WebSocket Hibernation attachments. The Worker also validates canonical URL-safe
room capabilities and same-site origins. Spreadsheet protocol and browser
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
```

`test:hibernation` uses the Workers Vitest runtime eviction helper to hibernate
connected WebSockets, then verifies that messages still relay and the
attachment-backed rate limit survives the Durable Object restart.

The generated MoonBit module is loaded by `entry.mjs`. Cloudflare's Worker and
Durable Object exports remain the only JavaScript adapter surface.

For deployment, configure the `cloudflare-worker` GitHub environment with
`CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`; the workflow deploys the
Worker and its static assets with Wrangler.
